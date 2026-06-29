# frozen_string_literal: true

require "bigdecimal"
require "csv"
require "digest"

module Evaluation
  class M25BenchmarkRunner
    DEFAULT_MANIFEST = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus/manifest.csv")

    def initialize(manifest_path: DEFAULT_MANIFEST, route_runner:, version_context: {}, real_corpus_report: nil)
      @manifest_path = Pathname(manifest_path)
      @route_runner = route_runner
      @version_context = version_context.deep_stringify_keys
      @real_corpus_report = real_corpus_report
    end

    def call
      cases = manifest_rows.map { |row| evaluate(row) }.sort_by { |entry| entry.fetch("fixture_id") }
      {
        "dataset" => dataset_metadata,
        "versions" => ordered_hash(version_context),
        "synthetic" => synthetic_summary(cases),
        "real_corpus" => real_corpus_summary,
        "cases" => cases
      }
    end

    private

    attr_reader :manifest_path, :route_runner, :version_context, :real_corpus_report

    def manifest_rows
      CSV.read(manifest_path, headers: true).map(&:to_h)
    end

    def evaluate(row)
      result = route_runner.call(row)
      metrics = result.fetch(:metrics, {}).deep_stringify_keys
      {
        "fixture_id" => row.fetch("fixture_id"),
        "kind" => row.fetch("kind"),
        "split" => row.fetch("split"),
        "expected_route" => row.fetch("expected_route"),
        "actual_route" => result.fetch(:route),
        "status" => result.fetch(:status),
        "schema_valid" => bool(result.fetch(:schema_valid, false)),
        "ground_truth_scored" => row.fetch("ground_truth").present?,
        "latency_ms" => integer(metrics["latency_ms"]),
        "peak_memory_mb" => integer(metrics["peak_memory_mb"]),
        "repair_attempts" => integer(metrics.fetch("repair_attempts", 0)),
        "quarantined" => result.fetch(:status).to_s == "quarantined",
        "oom" => result.fetch(:error_code, nil).to_s == "MODEL_OOM",
        "timeout" => result.fetch(:error_code, nil).to_s == "MODEL_TIMEOUT",
        "evidence_coverage" => decimal(metrics.fetch("evidence_coverage", 0)),
        "hallucinated_non_null_fields" => integer(metrics.fetch("hallucinated_non_null_fields", 0)),
        "field_count" => integer(metrics.fetch("field_count", 0)),
        "matched_field_count" => integer(metrics.fetch("matched_field_count", 0))
      }
    end

    def dataset_metadata
      {
        "manifest_sha256" => Digest::SHA256.hexdigest(manifest_path.read),
        "manifest_path" => manifest_path.basename.to_s,
        "case_count" => manifest_rows.length,
        "ground_truth_case_count" => manifest_rows.count { |row| row.fetch("ground_truth").present? }
      }
    end

    def synthetic_summary(cases)
      field_count = cases.sum { |entry| entry.fetch("field_count") }
      matched = cases.sum { |entry| entry.fetch("matched_field_count") }
      {
        "case_count" => cases.length,
        "ground_truth_scored_count" => cases.count { |entry| entry.fetch("ground_truth_scored") },
        "schema_valid_rate" => ratio(cases.count { |entry| entry.fetch("schema_valid") }, cases.length),
        "field_accuracy" => ratio(matched, field_count),
        "evidence_coverage" => ratio_decimal(cases.sum { |entry| BigDecimal(entry.fetch("evidence_coverage")) }, cases.length),
        "hallucinated_non_null_field_count" => cases.sum { |entry| entry.fetch("hallucinated_non_null_fields") },
        "median_latency_ms" => percentile(cases.map { |entry| entry.fetch("latency_ms") }, 0.50),
        "p95_latency_ms" => percentile(cases.map { |entry| entry.fetch("latency_ms") }, 0.95),
        "peak_memory_mb" => cases.map { |entry| entry.fetch("peak_memory_mb") }.max || 0,
        "oom_rate" => ratio(cases.count { |entry| entry.fetch("oom") }, cases.length),
        "timeout_rate" => ratio(cases.count { |entry| entry.fetch("timeout") }, cases.length),
        "repair_rate" => ratio(cases.count { |entry| entry.fetch("repair_attempts").positive? }, cases.length),
        "quarantine_rate" => ratio(cases.count { |entry| entry.fetch("quarantined") }, cases.length)
      }
    end

    def real_corpus_summary
      return { "available" => false, "metrics_merged_with_synthetic" => false } unless real_corpus_report

      real_corpus_report.merge("available" => true, "metrics_merged_with_synthetic" => false)
    end

    def percentile(values, point)
      compact = values.compact.sort
      return 0 if compact.empty?

      compact[[ (compact.length * point).ceil - 1, 0 ].max]
    end

    def ratio(numerator, denominator)
      return "0.000000" if denominator.zero?

      decimal(numerator.to_d / denominator)
    end

    def ratio_decimal(numerator, denominator)
      return "0.000000" if denominator.zero?

      decimal(numerator / denominator)
    end

    def decimal(value)
      format("%.6f", value)
    end

    def integer(value)
      value.nil? ? 0 : Integer(value)
    end

    def bool(value)
      value == true || value.to_s == "true"
    end

    def ordered_hash(hash)
      hash.keys.sort.to_h { |key| [ key, hash.fetch(key) ] }
    end
  end
end
