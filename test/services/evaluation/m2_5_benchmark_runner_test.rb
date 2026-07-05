# frozen_string_literal: true

require "canonical_test_helper"
require "json"
require_relative "../../../app/services/evaluation/m2_5_benchmark_runner"

module Evaluation
  class M25BenchmarkRunnerTest < Minitest::Test
    MANIFEST_PATH = Rails.root.join("test/fixtures/files/invoice_parser/samples/synthetic_corpus/manifest.csv")

    def test_report_represents_all_29_synthetic_fixtures
      report = run_report

      assert_equal 29, report.fetch("synthetic").fetch("case_count")
      assert_equal 29, report.fetch("cases").length
      assert_equal manifest_fixture_ids, report.fetch("cases").map { |entry| entry.fetch("fixture_id") }
      assert_equal 29, report.fetch("dataset").fetch("case_count")
      assert_equal 25, report.fetch("dataset").fetch("ground_truth_case_count")
    end

    def test_real_corpus_scorecard_is_separate_from_synthetic_metrics
      report = run_report
      real = report.fetch("real_corpus")

      assert_equal true, real.fetch("available")
      assert_equal false, real.fetch("metrics_merged_with_synthetic")
      assert_equal "permissioned_ground_truth_scorecard", real.fetch("claim_type")
      assert_equal 25, real.fetch("case_count")
      assert_equal 25, real.fetch("scored_case_count")
      refute report.fetch("synthetic").key?("real_field_accuracy")
      refute_equal report.fetch("synthetic").fetch("field_accuracy"), real.fetch("field_match_rate")
    end

    def test_required_latency_memory_failure_repair_evidence_and_hallucination_metrics_are_present
      report = run_report
      synthetic = report.fetch("synthetic")
      real = report.fetch("real_corpus")
      assert_equal 117, synthetic.fetch("p95_latency_ms")
      assert_equal 517, synthetic.fetch("peak_memory_mb")
      assert_equal "0.034483", synthetic.fetch("oom_rate")
      assert_equal "0.137931", synthetic.fetch("repair_rate")
      assert_equal "0.137931", synthetic.fetch("quarantine_rate")
      assert_equal "0.706897", synthetic.fetch("evidence_coverage")
      assert_equal 5, synthetic.fetch("hallucinated_non_null_field_count")
      assert_equal "0.880000", real.fetch("field_match_rate")
      assert_equal "0.760000", real.fetch("evidence_coverage_rate")
      assert_equal "0.040000", real.fetch("hallucination_rate")
      assert_equal 224, real.fetch("p95_latency_ms")
      assert_equal 1025, real.fetch("peak_memory_mb")
      assert_equal 1, real.fetch("oom_count")
      assert_equal "0.040000", real.fetch("oom_rate")
      assert_equal 2, real.fetch("repaired_count")
      assert_equal "0.080000", real.fetch("repair_rate")
      assert_equal 1, real.fetch("quarantine_count")
      assert_equal "0.040000", real.fetch("quarantine_rate")
    end

    def test_report_is_deterministic_content_free_and_records_rollback
      first_report = run_report
      second_report = run_report

      assert_equal JSON.generate(first_report), JSON.generate(second_report)
      assert_equal "manifest.csv", first_report.fetch("dataset").fetch("manifest_path")
      assert_equal true, first_report.fetch("real_corpus").fetch("rollback_verification").fetch("verified")
      assert_equal "local_open_source", first_report.fetch("real_corpus").fetch("rollback_verification").fetch("disabled_route")
      assert_equal "existing_provider", first_report.fetch("real_corpus").fetch("rollback_verification").fetch("restored_provider")
      assert_equal false, first_report.fetch("real_corpus").fetch("rollback_verification").fetch("schema_migration_required")

      encoded = JSON.generate(first_report)
      refute_includes encoded, "Acme Corp"
      refute_includes encoded, "Blue Supply"
      refute_includes encoded, "raw source text"
      refute_includes encoded, "evidence snippet"
      refute_includes encoded, "expected_canonical_path"
    end

    private

    def run_report
      Evaluation::M25BenchmarkRunner.new(
        manifest_path: MANIFEST_PATH,
        route_runner: FakeRouteRunner.new,
        version_context: {
          "model_revision" => "qwen3-vl-4b-instruct-fixture",
          "quantization" => "int4-fixture",
          "runtime" => "deterministic-local-client",
          "prompt_hash" => "sha256:m2-5-fixture",
          "device" => "cpu-fixture"
        },
        real_corpus_report: real_corpus_report
      ).call
    end

    def manifest_fixture_ids
      CSV.read(MANIFEST_PATH, headers: true).map { |row| row.fetch("fixture_id") }.sort
    end

    def real_corpus_report
      {
        "claim_type" => "permissioned_ground_truth_scorecard",
        "case_count" => 25,
        "scored_case_count" => 25,
        "field_count" => 100,
        "matched_field_count" => 88,
        "field_match_rate" => "0.880000",
        "evidence_coverage_rate" => "0.760000",
        "hallucination_rate" => "0.040000",
        "p95_latency_ms" => 224,
        "peak_memory_mb" => 1025,
        "oom_count" => 1,
        "oom_rate" => "0.040000",
        "repair_attempt_count" => 3,
        "repaired_count" => 2,
        "repair_rate" => "0.080000",
        "quarantine_count" => 1,
        "quarantine_rate" => "0.040000",
        "rollback_verification" => {
          "verified" => true,
          "disabled_route" => "local_open_source",
          "restored_provider" => "existing_provider",
          "schema_migration_required" => false
        }
      }
    end

    class FakeRouteRunner
      def call(row)
        index = row.fetch("fixture_id").scan(/\d+/).first.to_i
        status = row.fetch("expected_status") == "quarantined" ? :quarantined : :completed
        error_code = index == 13 ? :MODEL_OOM : nil

        {
          route: row.fetch("expected_route"),
          status: error_code ? :failed : status,
          schema_valid: row.fetch("expected_status") != "quarantined" && error_code.nil?,
          error_code: error_code,
          metrics: {
            latency_ms: 100 + index,
            peak_memory_mb: 500 + index,
            repair_attempts: index % 5 == 0 ? 1 : 0,
            evidence_coverage: evidence_coverage(index),
            hallucinated_non_null_fields: index % 4 == 0 ? 1 : 0,
            field_count: 4,
            matched_field_count: index % 6 == 0 ? 3 : 4
          },
          raw_text: "raw source text",
          supplier_name: "Acme Corp",
          evidence_text: "evidence snippet"
        }
      end

      private

      def evidence_coverage(index)
        index % 4 == 0 ? "0.500000" : "0.750000"
      end
    end
  end
end
