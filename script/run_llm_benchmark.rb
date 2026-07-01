# frozen_string_literal: true

require_relative "../config/environment"
require "csv"
require "json"
require "digest"
require "open3"
require "benchmark"

module Evaluation
  # Benchmarks a semantic-extraction model against the synthetic invoice
  # corpus by driving it through the real production pipeline
  # (Intake::UploadInspector -> LocalExtraction::RouteComposer ->
  # LocalExtraction::QwenSemanticAdapter -> Extraction::ProviderAdapter ->
  # Canonical::SchemaValidator), not a parallel reimplementation.
  #
  # Earlier versions of this script simulated OCR for image fixtures by
  # serializing the ground-truth JSON into a text block
  # (reconstruct_text_from_gt) and handing that to the model as if it were
  # OCR output. That measured a model's ability to copy an answer it had
  # already been given, not its ability to read a document — it invalidated
  # every image-route number in the model-selection report this script
  # produced. This version runs the real OCR/vision boundary
  # (LocalExtraction::GlmOcrClient + LocalExtraction::PdfRasterizer, the same
  # ones Extraction::DocumentExtractor uses in production) so image fixtures
  # are actually read from pixels.
  class LLMBenchmark
    MANIFEST_PATH = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus/manifest.csv")
    CORPUS_ROOT = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus")
    CSV_HEADERS = %w[fixture_id expected_route expected_status result_status schema_valid fields_matched fields_total accuracy latency_ms memory_kb error_code].freeze

    FIELDS = [
      { pointer: "/document_type", comparison: "exact" },
      { pointer: "/supplier/display_name", comparison: "normalized" },
      { pointer: "/invoice/number", comparison: "exact" },
      { pointer: "/invoice/issue_date", comparison: "exact" },
      { pointer: "/invoice/currency", comparison: "exact" },
      { pointer: "/totals/payable_amount", comparison: "decimal" },
      { pointer: "/totals/total_tax_amount", comparison: "decimal" }
    ].freeze

    def initialize(models:, fixture_ids: nil)
      @models = models
      @fixture_ids = fixture_ids
      @inspector = Intake::UploadInspector.new
      @ocr_client = LocalExtraction::GlmOcrClient.new
      @rasterizer = LocalExtraction::PdfRasterizer.new
    end

    # Runs every fixture in the manifest (or just `fixture_ids`, if given —
    # useful for a quick smoke test before a full multi-hour run). The 4
    # fixtures with no ground_truth (BAD-001/002/003, XML-002) are
    # unsafe/unsupported-input negatives with no "correct extraction" to
    # score against; they still run end-to-end so the failure/quarantine
    # behavior of the real Intake::UploadInspector is exercised and
    # reported, just without field-level scoring.
    def run
      manifest_rows = CSV.read(MANIFEST_PATH, headers: true).map(&:to_h)
      manifest_rows = manifest_rows.select { |row| @fixture_ids.include?(row.fetch("fixture_id")) } if @fixture_ids

      puts "Preparing #{manifest_rows.length} fixture inputs (real pypdf text + real glm-ocr OCR/vision bytes, shared across models)..."
      prepared = manifest_rows.to_h { |row| [ row.fetch("fixture_id"), prepare_fixture(row) ] }

      results = {}
      @models.each do |model|
        puts "\n=== Benchmarking semantic model: #{model} (OCR stage fixed at glm-ocr) ==="
        route_composer = build_route_composer(model)
        model_results = []

        csv_path = report_path(model)
        FileUtils.mkdir_p(File.dirname(csv_path))
        CSV.open(csv_path, "w") { |csv| csv << CSV_HEADERS }

        manifest_rows.each do |row|
          fixture_id = row.fetch("fixture_id")
          puts "Processing #{fixture_id}..."
          score = run_fixture(prepared.fetch(fixture_id), route_composer)
          puts "  Schema errors: #{score['schema_errors'].join(', ')}" if score["schema_errors"]&.any?
          score["fixture_id"] = fixture_id
          score["expected_route"] = row.fetch("expected_route")
          score["expected_status"] = row.fetch("expected_status")
          model_results << score
          append_to_report(csv_path, score)
        end

        results[model] = model_results
      end

      print_summary(results)
    end

    private

    def build_route_composer(model)
      LocalExtraction::RouteComposer.new(
        semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(client: LocalExtraction::OllamaClient.new(model: model))
      )
    end

    # Builds the same parser_output/ocr_output/images_bytes inputs
    # Extraction::DocumentExtractor would build for this file, once per
    # fixture so every candidate model is scored against identical input.
    def prepare_fixture(row)
      file_rel = row.fetch("file")
      full_path = CORPUS_ROOT.join(file_rel)
      bytes = full_path.binread

      inspection = @inspector.inspect_bytes(bytes, filename: File.basename(file_rel), content_type: nil)
      parser_result = parser_output(inspection, full_path)
      image_bytes = visual_bytes(inspection, parser_result, bytes)
      # ground_truth is blank (CSV parses it as nil) for the 4 unsafe/
      # unsupported-input negative fixtures — they have no "correct
      # extraction" to compare against.
      expected = row["ground_truth"].present? ? JSON.parse(CORPUS_ROOT.join(row["ground_truth"]).read) : nil

      { inspection:, parser_result:, ocr_result: ocr_output(image_bytes), image_bytes:, expected: }
    rescue StandardError => e
      { error: "PREP_ERROR: #{e.class}: #{e.message}" }
    end

    def run_fixture(inputs, route_composer)
      return score_result(nil, nil, inputs[:error], 0).merge("memory_kb" => LocalExtraction::DigitalPdfParser.current_memory_kb) if inputs[:error]

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      error_code = nil
      begin
        result = route_composer.call(
          inspection: inputs[:inspection],
          parser_output: inputs[:parser_result],
          ocr_output: inputs[:ocr_result],
          images_bytes: inputs[:image_bytes] ? [ inputs[:image_bytes] ] : []
        )
      rescue StandardError => e
        error_code = "BENCHMARK_HARNESS_ERROR: #{e.class}: #{e.message}"
      end
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      # Point-in-time RSS taken right after the call, not a continuous sample
      # during it, so this is a lower bound on peak memory, not the true peak.
      memory_kb = LocalExtraction::DigitalPdfParser.current_memory_kb

      score_result(inputs[:expected], result, error_code, latency_ms).merge("memory_kb" => memory_kb)
    end

    # Mirrors Extraction::DocumentExtractor#parser_output: only a digital PDF
    # with a real text layer gets native-parsed text.
    def parser_output(inspection, full_path)
      return {} unless inspection.sniffed_mime_type == "application/pdf"

      text = extract_pdf_text(full_path)
      return {} if text.to_s.strip.empty?

      { "version" => "benchmark-pypdf-v1", "page_count" => 1, "pages" => [ { "number" => 1, "text" => text } ], "text" => text }
    end

    # Mirrors Extraction::DocumentExtractor#visual_bytes: raw images go
    # straight to OCR/vision; a PDF is rasterized only when it has no usable
    # digital text layer, so a clean digital PDF doesn't pay for it.
    def visual_bytes(inspection, parser_result, bytes)
      case inspection.sniffed_mime_type
      when "image/jpeg", "image/png"
        bytes
      when "application/pdf"
        parser_result["text"].present? ? nil : @rasterizer.call(bytes: bytes)
      end
    end

    def ocr_output(image_bytes)
      return {} unless image_bytes

      response = @ocr_client.call(bytes: image_bytes)
      text = response.dig(:pages, 0, :text).to_s
      return {} if text.strip.empty?

      { "version" => "glm-ocr-boundary-v1", "page_count" => 1, "pages" => [ { "number" => 1, "text" => text } ], "text" => text }
    end

    def extract_pdf_text(pdf_path)
      python_script = "import pypdf, sys; reader = pypdf.PdfReader(sys.argv[1]); print('\\n'.join(page.extract_text() for page in reader.pages))"
      stdout, _stderr, status = Open3.capture3("python3", "-c", python_script, pdf_path.to_s)
      status.success? ? stdout : ""
    end

    # `expected` (ground truth) is nil for the 4 unsafe/unsupported-input
    # fixtures (BAD-001/002/003, XML-002) — those still produce a real
    # result (quarantined/unsupported_route) that must be scored on its own
    # terms (schema_valid/status/error_code), just without a FIELDS diff.
    # Forcing schema_valid to false whenever there's no ground truth would
    # misreport every one of those fixtures as a model failure even when the
    # pipeline did exactly what it should.
    def score_result(expected, result, error_code, latency_ms)
      out = {
        "schema_valid" => false,
        "status" => "harness_error",
        "error_code" => error_code,
        "latency_ms" => latency_ms,
        "fields_matched" => 0,
        "fields_total" => 0,
        "details" => {}
      }
      return out if error_code || result.nil?

      out["schema_valid"] = result.success?
      out["status"] = result.status
      out["error_code"] = result.error_code
      out["schema_errors"] = result.success? ? [] : Array(result.failure&.metadata&.dig(:schema_error_types)).map(&:to_s)

      return out if expected.nil?

      actual = result.success? ? result.attributes : result.provider_result&.attributes
      out["fields_total"] = FIELDS.length
      matched_count = 0

      FIELDS.each do |spec|
        pointer = spec.fetch(:pointer)
        expected_val = resolve_pointer(expected, pointer)
        actual_val = resolve_pointer(actual, pointer)
        matched = field_matches?(expected_val, actual_val, spec.fetch(:comparison))

        out["details"][pointer] = { "expected" => expected_val, "actual" => actual_val, "matched" => matched }
        matched_count += 1 if matched
      end

      out["fields_matched"] = matched_count
      out
    end

    def field_matches?(expected_val, actual_val, comparison)
      missing = ->(value) { value.nil? || value == :missing }
      return true if missing.call(expected_val) && missing.call(actual_val)
      return false if missing.call(expected_val) || missing.call(actual_val)

      case comparison
      when "exact" then expected_val.to_s.strip == actual_val.to_s.strip
      when "normalized" then expected_val.to_s.downcase.gsub(/\s+/, "") == actual_val.to_s.downcase.gsub(/\s+/, "")
      when "decimal"
        begin
          BigDecimal(expected_val.to_s) == BigDecimal(actual_val.to_s)
        rescue StandardError
          expected_val.to_s.strip == actual_val.to_s.strip
        end
      end
    end

    def resolve_pointer(doc, pointer)
      return :missing if doc.nil?

      parts = pointer.split("/")[1..]
      parts.reduce(doc) do |curr, part|
        return :missing if curr.nil? || curr == :missing

        if curr.is_a?(Hash)
          curr.key?(part) ? curr[part] : :missing
        elsif curr.is_a?(Array) && part =~ /\A\d+\z/
          idx = part.to_i
          idx < curr.length ? curr[idx] : :missing
        else
          return :missing
        end
      end
    end

    def report_path(model)
      Rails.root.join("tmp/benchmark/benchmark_results_#{model.gsub(/[:.\/]/, '_')}.csv")
    end

    def append_to_report(csv_path, r)
      # nil (blank in the CSV), not 0.0, when there's no ground truth to
      # score against — "not applicable" must stay distinguishable from "0%
      # accurate" for the 4 unsafe/unsupported-input fixtures.
      accuracy = r["fields_total"].zero? ? nil : (r["fields_matched"].to_f / r["fields_total"]).round(4)
      CSV.open(csv_path, "a") do |csv|
        csv << [
          r["fixture_id"], r["expected_route"], r["expected_status"], r["status"], r["schema_valid"],
          r["fields_matched"], r["fields_total"], accuracy, r["latency_ms"], r["memory_kb"], r["error_code"]
        ]
      end
    end

    def print_summary(results)
      puts "\n"
      puts "====================================================================="
      puts "                     LLM BENCHMARK FINAL SUMMARY                     "
      puts "     (OCR/vision stage: glm-ocr; digital text stage: pypdf)          "
      puts "====================================================================="
      puts "%-25s | %-12s | %-12s | %-12s | %-10s" % [ "Model", "Schema Valid", "Field Match", "Avg Latency", "Accuracy" ]
      puts "---------------------------------------------------------------------"

      summaries = []

      results.each do |model, model_results|
        total_cases = model_results.length
        schema_valid_count = model_results.count { |r| r["schema_valid"] }
        total_matched = model_results.sum { |r| r["fields_matched"] }
        total_fields = model_results.sum { |r| r["fields_total"] }
        avg_latency = total_cases.zero? ? 0 : (model_results.sum { |r| r["latency_ms"] }.to_f / total_cases).round
        overall_accuracy = total_fields.zero? ? 0.0 : (total_matched.to_f / total_fields)
        schema_valid_rate = total_cases.zero? ? 0.0 : (schema_valid_count.to_f / total_cases)

        puts "%-25s | %-12s | %-12s | %-12s | %-10s" % [
          model,
          "#{schema_valid_count}/#{total_cases} (#{(schema_valid_rate * 100).round}%)",
          "#{total_matched}/#{total_fields}",
          "#{avg_latency}ms",
          "#{(overall_accuracy * 100).round(2)}%"
        ]

        summaries << { model: model, schema_valid_rate: schema_valid_rate, overall_accuracy: overall_accuracy, avg_latency: avg_latency }
      end

      self.class.write_markdown_summary(summaries)
    end

    def self.compile_summary
      dir = Rails.root.join("tmp/benchmark")
      unless dir.directory?
        puts "No benchmark results directory found."
        return
      end

      csv_files = Dir.glob(dir.join("benchmark_results_*.csv"))
      if csv_files.empty?
        puts "No benchmark results CSV files found."
        return
      end

      summaries = csv_files.map do |csv_path|
        model_name = File.basename(csv_path, ".csv").sub("benchmark_results_", "").gsub("_", ":")
        rows = CSV.read(csv_path, headers: true).map(&:to_h)
        total_cases = rows.length
        schema_valid_count = rows.count { |r| r["schema_valid"] == "true" }
        total_matched = rows.sum { |r| r["fields_matched"].to_i }
        total_fields = rows.sum { |r| r["fields_total"].to_i }
        avg_latency = total_cases.zero? ? 0 : (rows.sum { |r| r["latency_ms"].to_i }.to_f / total_cases).round
        overall_accuracy = total_fields.zero? ? 0.0 : (total_matched.to_f / total_fields)
        schema_valid_rate = total_cases.zero? ? 0.0 : (schema_valid_count.to_f / total_cases)

        { model: model_name, schema_valid_rate: schema_valid_rate, overall_accuracy: overall_accuracy, avg_latency: avg_latency }
      end

      puts "\n"
      puts "====================================================================="
      puts "                     LLM BENCHMARK FINAL SUMMARY                     "
      puts "====================================================================="
      puts "%-25s | %-20s | %-20s | %-12s" % [ "Model", "Schema Valid Rate", "Field Match Accuracy", "Avg Latency" ]
      puts "---------------------------------------------------------------------"
      summaries.each do |s|
        puts "%-25s | %-20s | %-20s | %-12s" % [ s[:model], "#{(s[:schema_valid_rate] * 100).round(2)}%", "#{(s[:overall_accuracy] * 100).round(2)}%", "#{s[:avg_latency]}ms" ]
      end

      write_markdown_summary(summaries)
    end

    def self.write_markdown_summary(summaries)
      md_path = Rails.root.join("tmp/benchmark/summary.md")

      content = [ "# LLM Model Evaluation Report", "Date: #{Time.current.strftime('%Y-%m-%d')}", "",
                 "## Summary Table", "", "| Model | Schema Validity Rate | Field Match Accuracy | Average Latency |", "| --- | --- | --- | --- |" ]
      summaries.each { |s| content << "| #{s[:model]} | #{(s[:schema_valid_rate] * 100).round(2)}% | #{(s[:overall_accuracy] * 100).round(2)}% | #{s[:avg_latency]}ms |" }
      content << ""

      best = summaries.max_by { |s| [ s[:schema_valid_rate], s[:overall_accuracy], -s[:avg_latency] ] }
      content << "## Recommendation"
      content << ""
      content << "Based on the benchmark results, the best model for this task is **#{best[:model]}** with a field match accuracy of **#{(best[:overall_accuracy] * 100).round(2)}%** and a schema validity rate of **#{(best[:schema_valid_rate] * 100).round(2)}%**."
      content << ""

      File.write(md_path, content.join("\n"))
      puts "Wrote Markdown summary report to #{md_path}"
    end
  end
end

if __FILE__ == $0
  arg = ARGV[0]
  if arg == "summary"
    Evaluation::LLMBenchmark.compile_summary
  elsif arg
    Evaluation::LLMBenchmark.new(models: [ arg ]).run
  else
    puts "Usage: ruby script/run_llm_benchmark.rb [model_name | summary]"
    puts "Example: ruby script/run_llm_benchmark.rb qwen3-vl:4b"
  end
end
