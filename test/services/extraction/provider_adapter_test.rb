# frozen_string_literal: true

require "canonical_test_helper"

module Extraction
  class ProviderAdapterTest < Minitest::Test
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_001_minimal_visual_usd.json")
    SOURCE_SHA256 = "c7a72a7f3fc9f5c7209959fe15b7d29365ae0d4076d948f7b7a13f768d14fa36"

    Provider = Struct.new(:json_text, :metadata, :calls, keyword_init: true) do
      def call(**request)
        calls << request
        { json_text:, metadata: }
      end
    end

    def test_valid_provider_json_returns_candidate_and_content_free_attempt_metadata
      provider = Provider.new(json_text: valid_json, metadata: provider_metadata, calls: [])
      result = adapter(provider).extract(**request)

      assert result.success?
      assert_instance_of Canonical::Invoice, result.candidate
      assert_equal "fix_001_minimal_visual_usd", result.candidate.document_id
      assert_equal 1, provider.calls.size

      attempt = result.attempts.fetch(0)
      assert attempt.success?
      assert_nil attempt.error_code
      assert_equal SOURCE_SHA256, attempt.source_sha256
      assert_equal "visual_model", attempt.route
      assert_equal "US", attempt.region
      assert_equal "2.0", attempt.schema_version
      assert_equal "extract_invoice_v2", attempt.prompt_id
      assert_equal Digest::SHA256.hexdigest("extract_invoice_v2"), attempt.prompt_sha256
      assert_equal "managed-test@2026-06-29", attempt.provider
      assert_equal "adapter-1", attempt.provider_version
      assert_equal "vision-invoice", attempt.model
      assert_equal "2026-06", attempt.model_version
      assert_equal "0.011", attempt.cost
      assert_equal 120, attempt.input_tokens
      assert_equal 80, attempt.output_tokens
      assert_equal 347, attempt.latency_ms
      assert_equal result.idempotency_key, attempt.idempotency_key
      assert_equal 0, attempt.repair_attempt
      assert_equal 0, attempt.schema_error_count

      serialized_attempt = attempt.to_h.to_s
      refute_includes serialized_attempt, "Northstar"
      refute_includes serialized_attempt, "INV-2026-1042"
      refute_includes serialized_attempt, valid_json
    end

    def test_invalid_schema_returns_stable_code_without_raw_response_body
      attributes = valid_attributes
      attributes.delete("document_type")
      provider = Provider.new(json_text: JSON.generate(attributes), metadata: provider_metadata, calls: [])

      result = adapter(provider).extract(**request)

      assert result.rejected?
      assert_equal ProviderAdapter::SCHEMA_INVALID, result.error_code
      assert_nil result.candidate
      assert_equal 1, provider.calls.size

      attempt = result.attempts.fetch(0)
      assert attempt.failed?
      assert_equal ProviderAdapter::SCHEMA_INVALID, attempt.error_code
      assert_equal 1, attempt.schema_error_count
      assert_includes attempt.schema_error_types, "required"
      assert_includes attempt.schema_error_pointers, ""

      serialized_attempt = attempt.to_h.to_s
      refute_includes serialized_attempt, "Northstar"
      refute_includes serialized_attempt, "INV-2026-1042"
      refute_includes serialized_attempt, JSON.generate(attributes)
    end

    def test_duplicate_idempotency_key_reuses_candidate_without_duplicating_approved_state
      cache = {}
      provider = Provider.new(json_text: valid_json, metadata: provider_metadata, calls: [])
      service = adapter(provider, cache:)

      first = service.extract(**request)
      second = service.extract(**request)

      assert first.success?
      assert second.success?
      assert second.cached?
      assert_same first.candidate, second.candidate
      assert_equal first.idempotency_key, second.idempotency_key
      assert_equal 1, provider.calls.size
      assert_equal 1, cache.size
      assert_equal 1, first.attempts.size
      assert_empty second.attempts
    end

    def test_repair_applies_only_listed_fields_and_exactly_once
      provider = Provider.new(json_text: valid_json, metadata: provider_metadata, calls: [])
      service = adapter(provider)
      initial = service.extract(**request)

      repaired = service.repair(
        result: initial,
        patch: { invoice: { payment_terms_text: "Due on receipt" } },
        allowed_paths: [ "/invoice/payment_terms_text" ]
      )

      assert repaired.success?
      assert_equal 1, repaired.repair_attempts
      assert_equal "Due on receipt", repaired.candidate.to_h.fetch("invoice").fetch("payment_terms_text")
      assert_equal initial.candidate.to_h.except("invoice"), repaired.candidate.to_h.except("invoice")
      assert_equal initial.candidate.to_h.fetch("invoice").except("payment_terms_text"), repaired.candidate.to_h.fetch("invoice").except("payment_terms_text")
      assert_equal 2, repaired.attempts.size
      assert_equal 1, repaired.attempts.last.repair_attempt

      second = service.repair(
        result: repaired,
        patch: { invoice: { due_date: "2026-07-20" } },
        allowed_paths: [ "/invoice/due_date" ]
      )

      assert second.rejected?
      assert_equal ProviderAdapter::REPAIR_LIMIT_EXCEEDED, second.error_code
      assert_equal 1, second.repair_attempts
    end

    def test_repair_rejects_patch_outside_allowed_paths
      provider = Provider.new(json_text: valid_json, metadata: provider_metadata, calls: [])
      service = adapter(provider)
      initial = service.extract(**request)

      repaired = service.repair(
        result: initial,
        patch: { invoice: { number: "INV-CHANGED", payment_terms_text: "Due on receipt" } },
        allowed_paths: [ "/invoice/payment_terms_text" ]
      )

      assert repaired.rejected?
      assert_equal ProviderAdapter::REPAIR_PATH_NOT_ALLOWED, repaired.error_code
      assert_equal 0, repaired.repair_attempts
      assert_equal initial.candidate.to_h, repaired.attributes
    end

    private

    def adapter(provider, cache: {})
      ProviderAdapter.new(provider:, cache:)
    end

    def request
      {
        source_sha256: SOURCE_SHA256,
        route: "visual_model",
        region: "US",
        schema_version: "2.0",
        prompt_id: "extract_invoice_v2",
        provider_id: "managed-test",
        provider_version: "2026-06-29",
        model: "vision-invoice",
        model_version: "2026-06"
      }
    end

    def provider_metadata
      {
        version: "adapter-1",
        model: "vision-invoice",
        model_version: "2026-06",
        cost: "0.011",
        tokens: { input: 120, output: 80 },
        latency_ms: 347,
        raw_response_body: valid_json,
        signed_url: "https://example.invalid/signed-secret"
      }
    end

    def valid_json
      FIXTURE_PATH.read
    end

    def valid_attributes
      JSON.parse(valid_json)
    end
  end
end
