# frozen_string_literal: true

require "canonical_test_helper"
require "digest"

module Evaluation
  class GoldenSetRunnerTest < Minitest::Test
    MANIFEST_PATH = Rails.root.join("test/fixtures/files/benchmark/golden_set_manifest.json")
    CANONICAL_FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")
    VERSION_CONTEXT = {
      "schema_version" => "2.0",
      "prompt_hash" => "sha256:test-prompt",
      "provider_version" => "fake-provider-v1",
      "parser_version" => "fake-parser-v1",
      "format_registry_version" => "formats-v1",
      "currency_registry_version" => "currencies-v1"
    }.freeze

    def test_repeated_runs_are_byte_identical_for_same_inputs
      extractor = FakeExtractor.new
      first_report = Evaluation::GoldenSetRunner.new(
        manifest_path: MANIFEST_PATH,
        extractor: extractor,
        version_context: VERSION_CONTEXT
      ).call
      second_report = Evaluation::GoldenSetRunner.new(
        manifest_path: MANIFEST_PATH,
        extractor: extractor,
        version_context: VERSION_CONTEXT
      ).call

      assert_equal JSON.generate(first_report), JSON.generate(second_report)
    end

    def test_report_orders_cases_and_fields_deterministically
      report = run_report

      assert_equal [ "structured_case", "visual_case" ], report.fetch("cases").map { |entry| entry.fetch("id") }
      visual = report.fetch("cases").find { |entry| entry.fetch("id") == "visual_case" }
      assert_equal [ "/invoice/currency", "/invoice/number", "/totals/payable_amount" ],
        visual.fetch("fields").map { |field| field.fetch("pointer") }
    end

    def test_profiles_separate_visual_and_structured_route_metrics
      report = run_report
      profile = report.fetch("profiles").fetch(0)
      routes = profile.fetch("routes")

      assert_equal "global_generic_v1", profile.fetch("profile")
      assert_equal [ "structured_xml", "visual_model" ], routes.map { |route| route.fetch("route") }
      assert_equal 1, routes.find { |route| route.fetch("route") == "visual_model" }.fetch("case_count")
      assert_equal 1, routes.find { |route| route.fetch("route") == "structured_xml" }.fetch("case_count")
      assert_equal "0.800000", report.fetch("summary").fetch("accuracy")
    end

    def test_field_mismatches_and_decimal_exact_matches_are_scored_correctly
      report = run_report
      cases = report.fetch("cases")
      structured = cases.find { |entry| entry.fetch("id") == "structured_case" }
      visual = cases.find { |entry| entry.fetch("id") == "visual_case" }

      structured_currency = structured.fetch("fields").find { |field| field.fetch("pointer") == "/invoice/currency" }
      structured_payable = structured.fetch("fields").find { |field| field.fetch("pointer") == "/totals/payable_amount" }
      visual_number = visual.fetch("fields").find { |field| field.fetch("pointer") == "/invoice/number" }
      visual_payable = visual.fetch("fields").find { |field| field.fetch("pointer") == "/totals/payable_amount" }

      refute structured_currency.fetch("matched")
      assert_equal "FIELD_MISMATCH", structured_currency.fetch("error_code")
      assert structured_payable.fetch("matched"), "1200.0 and 1200.00 should be an exact decimal-value match"
      assert visual_number.fetch("matched"), "normalized string comparison should ignore case and surrounding whitespace"
      assert visual_payable.fetch("matched"), "100.0 and 100.00 should be an exact decimal-value match"
      assert_equal 5, report.fetch("summary").fetch("field_count")
      assert_equal 4, report.fetch("summary").fetch("matched_field_count")
    end

    def test_report_contains_manifest_hash_versions_route_cost_metadata_without_source_content
      report = run_report
      encoded = JSON.generate(report)

      assert_equal Digest::SHA256.hexdigest(MANIFEST_PATH.read), report.fetch("dataset").fetch("manifest_sha256")
      assert_equal VERSION_CONTEXT, report.fetch("versions")
      assert_equal "2.0", report.fetch("versions").fetch("schema_version")
      assert_equal "sha256:test-prompt", report.fetch("versions").fetch("prompt_hash")
      assert_equal "fake-provider-v1", report.fetch("versions").fetch("provider_version")
      assert_equal "fake-parser-v1", report.fetch("versions").fetch("parser_version")
      assert_equal "formats-v1", report.fetch("versions").fetch("format_registry_version")
      assert_equal "currencies-v1", report.fetch("versions").fetch("currency_registry_version")

      visual = report.fetch("cases").find { |entry| entry.fetch("id") == "visual_case" }
      assert_equal 42, visual.fetch("latency_ms")
      assert_equal({ "currency" => "USD", "amount" => "0.0001", "input_tokens" => 10, "output_tokens" => 20 }, visual.fetch("cost"))
      assert_equal "0.0003", report.fetch("summary").fetch("cost").fetch("amount")

      refute_includes encoded, "Northstar"
      refute_includes encoded, "INV-2026-1042"
      refute_includes encoded, "Invoice No."
      refute_includes encoded, "raw canonical response body"
      refute_includes encoded, "https://signed.example"
      refute_includes encoded, "expected_canonical_path"
    end

    private

    def run_report
      Evaluation::GoldenSetRunner.new(
        manifest_path: MANIFEST_PATH,
        extractor: FakeExtractor.new,
        version_context: VERSION_CONTEXT
      ).call
    end

    class FakeExtractor
      def call(case_config)
        case case_config.fetch("id")
        when "visual_case"
          payload = JSON.parse(CANONICAL_FIXTURE_DIR.join("fix_001_minimal_visual_usd.json").read)
          payload.fetch("invoice")["number"] = " inv-2026-1042 "
          payload.fetch("totals")["payable_amount"] = "100.0"
          result(payload, latency_ms: 42, amount: "0.000100", input_tokens: 10, output_tokens: 20)
        when "structured_case"
          payload = JSON.parse(CANONICAL_FIXTURE_DIR.join("fix_005_generic_vat_eur.json").read)
          payload.fetch("invoice")["currency"] = "GBP"
          payload.fetch("totals")["payable_amount"] = "1200.0"
          result(payload, latency_ms: 7, amount: "0.000200", input_tokens: 5, output_tokens: 8)
        else
          raise KeyError, "unknown benchmark case"
        end
      end

      private

      def result(payload, latency_ms:, amount:, input_tokens:, output_tokens:)
        {
          json: JSON.generate(payload),
          metadata: {
            latency_ms: latency_ms,
            cost: {
              currency: "USD",
              amount: amount,
              input_tokens: input_tokens,
              output_tokens: output_tokens
            },
            response_body: "raw canonical response body",
            signed_url: "https://signed.example/document"
          }
        }
      end
    end
  end
end
