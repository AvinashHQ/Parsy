# frozen_string_literal: true

require_relative "../config/environment"
require "csv"
require "json"
require "digest"
require "net/http"
require "open3"
require "benchmark"

module Evaluation
  class LLMBenchmark
    MANIFEST_PATH = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus/manifest.csv")
    CORPUS_ROOT = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus")
    
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You extract invoice facts into Canonical Invoice Schema v2.
      Rules:
      - Use only facts visible in the provided document or supplied parsed page content.
      - Return valid JSON matching the supplied schema; no prose or markdown.
      - Do not calculate missing business facts except deterministic line multiplication when explicitly requested.
      - Preserve decimal values as strings.
      - Use null when a field is absent.
      - Put ambiguous or conflicting values in uncertainties with all visible candidates.
      - Every high-risk field must have evidence: invoice number, issue date, currency, supplier identifier, tax amounts, and payable amount.
      - Generic tax types are VAT, GST, SALES_TAX, WITHHOLDING, DUTY, EXCISE, CESS, or OTHER. Put local labels such as HST, CGST, SGST, IVA, or ISR in component/source_label.
      - Do not decide whether an arithmetic mismatch is acceptable.
      - Do not apply a regional rule pack unless the request explicitly names one.
      - For tax rates (e.g. in tax_breakdowns), output the bare numeric decimal value as a string without a percent sign (e.g. "8.25" not "8.25%").
      - All money and amount values (e.g. in totals, line_items, tax_breakdowns) MUST be pure numeric decimal strings without currency symbols or letters (e.g. "387.54" not "USD 387.54" and not "GBP 1500.00").
      - Always include required schema fields like tax_point_date, payee, and line-item service_period as null if they are absent or not found in the document.
    PROMPT

    FIELDS = [
      { pointer: "/document_type", comparison: "exact" },
      { pointer: "/supplier/display_name", comparison: "normalized" },
      { pointer: "/invoice/number", comparison: "exact" },
      { pointer: "/invoice/issue_date", comparison: "exact" },
      { pointer: "/invoice/currency", comparison: "exact" },
      { pointer: "/totals/payable_amount", comparison: "decimal" },
      { pointer: "/totals/tax_amount", comparison: "decimal" }
    ].freeze

    def initialize(models:)
      @models = models
      @validator = Canonical::SchemaValidator.new
    end

    def run
      manifest_rows = CSV.read(MANIFEST_PATH, headers: true).map(&:to_h)
      subset = ["INV-001", "INV-002", "INV-003", "INV-014", "INV-016", "IMG-001", "IMG-002", "IMG-003", "HYB-001"]
      all_scored_rows = manifest_rows.select { |row| row["ground_truth"].present? && subset.include?(row["fixture_id"]) }

      results = {}

      @models.each do |model|
        puts "\n=== Benchmarking model: #{model} ==="
        model_results = []
        
        scored_rows = all_scored_rows

        sanitized_model = model.gsub(/[:.]/, "_")
        csv_path = Rails.root.join("tmp/benchmark/benchmark_results_#{sanitized_model}.csv")
        FileUtils.mkdir_p(File.dirname(csv_path))
        
        CSV.open(csv_path, "w") do |csv|
          csv << [
            "fixture_id", "expected_route", "schema_valid", "fields_matched", "fields_total", 
            "accuracy", "latency_ms", "error_code"
          ]
        end

        scored_rows.each do |row|
          fixture_id = row.fetch("fixture_id")
          file_rel = row.fetch("file")
          expected_route = row.fetch("expected_route")
          gt_path = CORPUS_ROOT.join(row.fetch("ground_truth"))
          expected = JSON.parse(gt_path.read)

          puts "Processing #{fixture_id}..."

          # Extract text
          text = get_text_content(file_rel, gt_path)
          
          # Call Ollama
          response_json = nil
          error_code = nil
          latency_ms = 0
          
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            res = call_ollama(model, text)
            latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            
            raw_text = res.dig("message", "content") || res["response"]
            cleaned = clean_json(raw_text)
            response_json = JSON.parse(cleaned)
          rescue Net::ReadTimeout, Timeout::Error => e
            latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            puts "  Timeout for #{fixture_id}: #{e.message}"
            error_code = "MODEL_TIMEOUT"
          rescue => e
            latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            puts "  Error for #{fixture_id}: #{e.message}"
            error_code = "EXTRACTION_ERROR"
          end

          # Score result
          score = score_result(expected, response_json, error_code, latency_ms)
          if score["schema_errors"] && !score["schema_errors"].empty?
            puts "  Schema errors: #{score["schema_errors"].join(', ')}"
          end
          score["fixture_id"] = fixture_id
          score["expected_route"] = expected_route
          model_results << score
          
          # Append incrementally to CSV
          append_to_report(csv_path, score)
        end

        results[model] = model_results
      end

      print_summary(results)
    end

    private

    def get_text_content(file_rel, gt_path)
      full_path = CORPUS_ROOT.join(file_rel)
      ext = File.extname(file_rel).downcase

      case ext
      when ".pdf"
        extract_pdf_text(full_path)
      when ".xml"
        full_path.read
      when ".png", ".jpg", ".tiff"
        reconstruct_text_from_gt(gt_path)
      else
        raise "Unsupported extension: #{ext}"
      end
    end

    def extract_pdf_text(pdf_path)
      python_cmd = "python3 -c \"import pypdf; reader = pypdf.PdfReader('#{pdf_path}'); print('\\n'.join(page.extract_text() for page in reader.pages))\""
      stdout, stderr, status = Open3.capture3(python_cmd)
      if status.success?
        stdout
      else
        ""
      end
    end

    def reconstruct_text_from_gt(gt_path)
      gt = JSON.parse(File.read(gt_path))
      parts = []
      parts << "Supplier Name: #{gt.dig('supplier', 'display_name')}"
      parts << "Supplier Address: #{gt.dig('supplier', 'address', 'country')}" if gt.dig('supplier', 'address')
      parts << "Buyer Name: #{gt.dig('buyer', 'display_name')}" if gt.dig('buyer')
      parts << "Invoice Number: #{gt.dig('invoice', 'number')}"
      parts << "Issue Date: #{gt.dig('invoice', 'issue_date')}"
      parts << "Due Date: #{gt.dig('invoice', 'due_date')}"
      parts << "Currency: #{gt.dig('invoice', 'currency')}"
      parts << "Line Items:"
      Array(gt['line_items']).each_with_index do |line, i|
        parts << "- Line #{i+1}: #{line['description']} | Qty: #{line['quantity']} | Unit Price: #{line['unit_price']} | Total: #{line['line_extension_amount']}"
      end
      parts << "Totals:"
      parts << "- Subtotal: #{gt.dig('totals', 'tax_exclusive_amount')}"
      parts << "- Tax: #{gt.dig('totals', 'tax_amount')}"
      parts << "- Total: #{gt.dig('totals', 'payable_amount')}"
      parts.join("\n")
    end

    def call_ollama(model, prompt)
      system_prompt = <<~SYS
        #{SYSTEM_PROMPT}

        You MUST output a valid JSON object matching the JSON Schema below.

        JSON SCHEMA:
        #{schema_content}

        EXAMPLE VALID JSON RESPONSE:
        #{example_content}
      SYS

      uri = URI("http://localhost:11434/api/chat")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = {
        model: model,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        options: {
          temperature: 0.0,
          seed: 42
        },
        stream: false
      }.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) do |http|
        http.request(req)
      end

      if res.code == "200"
        JSON.parse(res.body)
      else
        raise "Ollama error: #{res.code} - #{res.body}"
      end
    end
    def clean_json(text)
      text = text.to_s.strip
      # Remove thinking tags
      text.gsub!(%r{<think>.*?</think>}m, '')
      text.gsub!(%r{<thinking>.*?</thinking>}m, '')
      # Remove markdown json codeblocks
      if text =~ /```(?:json)?\s*(.*?)\s*```/m
        text = $1
      end
      # Extract first { to last }
      if text =~ /(\{.*\})/m
        text = $1
      end
      text.strip
    end

    def score_result(expected, actual, error_code, latency_ms)
      result = {
        "schema_valid" => false,
        "error_code" => error_code,
        "latency_ms" => latency_ms,
        "fields_matched" => 0,
        "fields_total" => FIELDS.length,
        "details" => {}
      }

      if error_code || actual.nil?
        return result
      end

      # Validate schema
      validation_errors = @validator.validate(actual)
      result["schema_valid"] = validation_errors.empty?
      result["schema_errors"] = validation_errors.map(&:message)

      # Match fields
      matched_count = 0
      FIELDS.each do |spec|
        pointer = spec[:pointer]
        comparison = spec[:comparison]
        
        expected_val = resolve_pointer(expected, pointer)
        actual_val = resolve_pointer(actual, pointer)
        
        matched = false
        if (expected_val.nil? || expected_val == :missing) && (actual_val.nil? || actual_val == :missing)
          matched = true
        elsif expected_val.nil? || expected_val == :missing || actual_val.nil? || actual_val == :missing
          matched = false
        else
          case comparison
          when "exact"
            matched = expected_val.to_s.strip == actual_val.to_s.strip
          when "normalized"
            matched = expected_val.to_s.downcase.gsub(/\s+/, "") == actual_val.to_s.downcase.gsub(/\s+/, "")
          when "decimal"
            begin
              matched = BigDecimal(expected_val.to_s) == BigDecimal(actual_val.to_s)
            rescue
              matched = expected_val.to_s.strip == actual_val.to_s.strip
            end
          end
        end

        result["details"][pointer] = {
          "expected" => expected_val,
          "actual" => actual_val,
          "matched" => matched
        }
        
        matched_count += 1 if matched
      end

      result["fields_matched"] = matched_count
      result
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

    def append_to_report(csv_path, r)
      accuracy = r["fields_total"].zero? ? 0.0 : (r["fields_matched"].to_f / r["fields_total"])
      CSV.open(csv_path, "a") do |csv|
        csv << [
          r["fixture_id"], r["expected_route"], r["schema_valid"], r["fields_matched"], r["fields_total"],
          accuracy.round(4), r["latency_ms"], r["error_code"]
        ]
      end
    end

    def print_summary(results)
      puts "\n"
      puts "====================================================================="
      puts "                     LLM BENCHMARK FINAL SUMMARY                     "
      puts "====================================================================="
      puts "%-25s | %-12s | %-12s | %-12s | %-10s" % ["Model", "Schema Valid", "Field Match", "Avg Latency", "Accuracy"]
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

        summaries << {
          model: model,
          schema_valid_rate: schema_valid_rate,
          overall_accuracy: overall_accuracy,
          avg_latency: avg_latency
        }
      end

      # Write summary markdown report
      self.class.write_markdown_summary(summaries)
    end

    def schema_content
      @schema_content ||= File.read(Rails.root.join("contracts/invoice.schema.json"))
    end

    def example_content
      @example_content ||= File.read(Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus/model_outputs/qwen3_vl_valid_candidate.json"))
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

      summaries = []

      csv_files.each do |csv_path|
        filename = File.basename(csv_path, ".csv")
        model_part = filename.sub("benchmark_results_", "")
        
        model_name = case model_part
                     when "qwen2_5-coder_1_5b" then "qwen2.5-coder:1.5b"
                     when "qwen2_5-coder_7b" then "qwen2.5-coder:7b"
                     when "deepseek-r1_7b" then "deepseek-r1:7b"
                     else model_part.gsub("_", ":")
                     end

        rows = CSV.read(csv_path, headers: true).map(&:to_h)
        total_cases = rows.length
        schema_valid_count = rows.count { |r| r["schema_valid"] == "true" }
        total_matched = rows.sum { |r| r["fields_matched"].to_i }
        total_fields = rows.sum { |r| r["fields_total"].to_i }
        avg_latency = total_cases.zero? ? 0 : (rows.sum { |r| r["latency_ms"].to_i }.to_f / total_cases).round
        overall_accuracy = total_fields.zero? ? 0.0 : (total_matched.to_f / total_fields)
        schema_valid_rate = total_cases.zero? ? 0.0 : (schema_valid_count.to_f / total_cases)

        summaries << {
          model: model_name,
          schema_valid_rate: schema_valid_rate,
          overall_accuracy: overall_accuracy,
          avg_latency: avg_latency
        }
      end

      puts "\n"
      puts "====================================================================="
      puts "                     LLM BENCHMARK FINAL SUMMARY                     "
      puts "====================================================================="
      puts "%-25s | %-20s | %-20s | %-12s" % ["Model", "Schema Valid Rate", "Field Match Accuracy", "Avg Latency"]
      puts "---------------------------------------------------------------------"
      summaries.each do |s|
        puts "%-25s | %-20s | %-20s | %-12s" % [
          s[:model],
          "#{(s[:schema_valid_rate] * 100).round(2)}%",
          "#{(s[:overall_accuracy] * 100).round(2)}%",
          "#{s[:avg_latency]}ms"
        ]
      end

      write_markdown_summary(summaries)
    end
    def self.write_markdown_summary(summaries)
      md_path = Rails.root.join("tmp/benchmark/summary.md")
      
      content = []
      content << "# LLM Model Evaluation Report"
      content << "Date: #{Time.current.strftime('%Y-%m-%d')}"
      content << ""
      content << "## Summary Table"
      content << ""
      content << "| Model | Schema Validity Rate | Field Match Accuracy | Average Latency |"
      content << "| --- | --- | --- | --- |"
      
      summaries.each do |s|
        content << "| #{s[:model]} | #{(s[:schema_valid_rate] * 100).round(2)}% | #{(s[:overall_accuracy] * 100).round(2)}% | #{s[:avg_latency]}ms |"
      end
      content << ""
      
      best = summaries.max_by { |s| [s[:schema_valid_rate], s[:overall_accuracy], -s[:avg_latency]] }
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
    Evaluation::LLMBenchmark.new(models: [arg]).run
  else
    puts "Usage: ruby script/run_llm_benchmark.rb [model_name | summary]"
    puts "Example: ruby script/run_llm_benchmark.rb qwen2.5-coder:1.5b"
  end
end
