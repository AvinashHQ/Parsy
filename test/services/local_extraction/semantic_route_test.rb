# frozen_string_literal: true

require "test_helper"

module LocalExtraction
  class SemanticRouteTest < ActiveSupport::TestCase
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_001_minimal_visual_usd.json")
    PDF_BYTES = "%PDF-1.7\nlocal semantic fixture\n%%EOF".b
    SOURCE_SHA256 = Digest::SHA256.hexdigest(PDF_BYTES)

    class FixtureClient
      attr_reader :extract_requests, :repair_requests

      def initialize(json_text:, metadata: {}, repair_patch: nil, error: nil)
        @json_text = json_text
        @metadata = metadata
        @repair_patch = repair_patch
        @error = error
        @extract_requests = []
        @repair_requests = []
      end

      def extract_invoice(request)
        extract_requests << request
        raise error if error

        {
          json_text: json_text,
          metadata: metadata
        }
      end

      def repair_invoice(request)
        repair_requests << request
        { patch: repair_patch || {} }
      end

      private

      attr_reader :json_text, :metadata, :repair_patch, :error
    end

    test "supported fixture returns schema-valid candidate with deterministic qwen provenance" do
      client = FixtureClient.new(
        json_text: valid_json,
        metadata: {
          latency_ms: 41,
          confidence: 0.01,
          raw_response_body: valid_json,
          signed_url: "https://example.invalid/secret"
        }
      )
      result = composer(client:).call(inspection:, parser_output:, ocr_output:)

      assert result.success?
      assert_instance_of Canonical::Invoice, result.candidate
      assert_equal "fix_001_minimal_visual_usd", result.candidate.document_id
      assert_equal 1, client.extract_requests.size
      assert_equal SOURCE_SHA256, client.extract_requests.first.fetch(:document).fetch(:source_sha256)
      assert_equal QwenSemanticAdapter::PROMPT_SHA256, client.extract_requests.first.fetch(:prompt_sha256)
      assert_equal({ temperature: 0, top_p: 1, top_k: 1, seed: 0, max_repair_attempts: 1 }, client.extract_requests.first.fetch(:deterministic_settings))

      attempt = result.attempts.fetch(0)
      assert attempt.success?
      assert_equal "local_open_source", attempt.provider
      assert_equal "qwen3-vl:4b", attempt.model
      assert_equal "qwen3-vl-2026-06", attempt.model_version
      assert_equal 41, attempt.latency_ms
      assert_equal result.idempotency_key, attempt.idempotency_key

      provenance = result.provenance
      assert_equal "qwen3-vl-2026-06", provenance.fetch(:model_revision)
      assert_equal "mlx", provenance.fetch(:runtime)
      assert_equal "int4", provenance.fetch(:quantization)
      assert_equal "apple-m4", provenance.fetch(:device)
      assert_equal QwenSemanticAdapter::PROMPT_SHA256, provenance.fetch(:prompt_sha256)
      assert_equal 41, provenance.fetch(:latency_ms)
      refute_includes provenance.to_s, "Northstar"
      refute_includes provenance.to_s, "INV-2026-1042"
      refute_includes provenance.to_s, valid_json
      refute_includes provenance.to_s, "confidence"
    end

    test "provider_id/model/provider_version are configurable so a cloud client can reuse this adapter" do
      client = FixtureClient.new(json_text: valid_json, metadata: { latency_ms: 22 })
      adapter = QwenSemanticAdapter.new(
        client:,
        provider_id: "google_gemini",
        model: "gemini-2.5-flash",
        provider_version: "gemini-cloud-v1",
        runtime: "gemini_cloud",
        quantization: "n/a",
        device: "managed_cloud"
      )
      result = RouteComposer.new(semantic_adapter: adapter).call(inspection:, parser_output:, ocr_output:)

      assert result.success?
      attempt = result.attempts.fetch(0)
      assert_equal "google_gemini", attempt.provider
      assert_equal "gemini-2.5-flash", attempt.model
      assert_equal "gemini-2.5-flash", result.provenance.fetch(:model)
      assert_equal "gemini_cloud", result.provenance.fetch(:runtime)
      assert_equal "n/a", result.provenance.fetch(:quantization)
      assert_equal "managed_cloud", result.provenance.fetch(:device)
      # the shared prompt (field contract + worked example) is provider-independent
      assert_equal QwenSemanticAdapter::PROMPT_SHA256, client.extract_requests.first.fetch(:prompt_sha256)
    end

    test "schema invalid fixture is explicit schema error and ignores model confidence" do
      attributes = valid_attributes
      attributes.delete("document_type")
      client = FixtureClient.new(
        json_text: JSON.generate(attributes),
        metadata: { latency_ms: 9, confidence: 0.999, raw_response_body: JSON.generate(attributes) }
      )
      result = composer(client:).call(inspection:, parser_output:, ocr_output:)

      assert result.needs_review?
      assert_equal Extraction::ProviderAdapter::SCHEMA_INVALID, result.error_code
      assert_nil result.candidate
      assert_nil result.attributes
      assert_equal 1, client.extract_requests.size
      assert result.attempts.first.schema_error_count.positive?
      assert_includes result.failure.metadata.fetch(:schema_error_types), "required"
      refute_includes result.to_h.to_s, "Northstar"
      refute_includes result.to_h.to_s, "INV-2026-1042"
      refute_includes result.to_h.to_s, JSON.generate(attributes)
      refute_includes result.provenance.to_s, "confidence"
    end

    test "repeat document and config reuses idempotent candidate" do
      cache = {}
      client = FixtureClient.new(json_text: valid_json, metadata: { latency_ms: 15 })
      route = composer(client:, cache:)

      first = route.call(inspection:, parser_output:, ocr_output:)
      second = route.call(inspection:, parser_output:, ocr_output:)

      assert first.success?
      assert second.success?
      assert second.cached?
      assert_same first.candidate, second.candidate
      assert_equal first.idempotency_key, second.idempotency_key
      assert_equal 1, client.extract_requests.size
      assert_empty second.attempts
    end

    test "repair asks local client once and applies only allowed paths" do
      client = FixtureClient.new(
        json_text: valid_json,
        metadata: { latency_ms: 7 },
        repair_patch: { invoice: { payment_terms_text: "Due on receipt" } }
      )
      route = composer(client:)
      initial = route.call(inspection:, parser_output:, ocr_output:)

      repaired = route.repair(
        result: initial,
        inspection:,
        allowed_paths: [ "/invoice/payment_terms_text" ],
        parser_output:,
        ocr_output:
      )

      assert repaired.success?
      assert_equal 1, client.repair_requests.size
      assert_equal [ "/invoice/payment_terms_text" ], client.repair_requests.first.fetch(:allowed_paths)
      assert_equal 1, repaired.repair_attempts
      assert_equal "Due on receipt", repaired.candidate.to_h.fetch("invoice").fetch("payment_terms_text")

      second = route.repair(
        result: repaired,
        inspection:,
        allowed_paths: [ "/invoice/due_date" ],
        parser_output:,
        ocr_output:
      )
      assert second.needs_review?
      assert_equal Extraction::ProviderAdapter::REPAIR_LIMIT_EXCEEDED, second.error_code
      assert_equal 1, client.repair_requests.size
    end

    test "repair patch outside allowed paths is rejected without applying content" do
      client = FixtureClient.new(
        json_text: valid_json,
        metadata: { latency_ms: 7 },
        repair_patch: { invoice: { number: "INV-CHANGED" } }
      )
      route = composer(client:)
      initial = route.call(inspection:, parser_output:, ocr_output:)

      repaired = route.repair(
        result: initial,
        inspection:,
        allowed_paths: [ "/invoice/payment_terms_text" ],
        parser_output:,
        ocr_output:
      )

      assert repaired.needs_review?
      assert_equal Extraction::ProviderAdapter::REPAIR_PATH_NOT_ALLOWED, repaired.error_code
      assert_equal 0, repaired.repair_attempts
      assert_nil repaired.attributes
      refute_includes repaired.to_h.to_s, "INV-CHANGED"
    end

    test "failure cases route content-free safe failures" do
      invalid_json = composer(client: FixtureClient.new(json_text: "{ Northstar INV-2026-1042", metadata: { latency_ms: 3 })).call(
        inspection:,
        parser_output:,
        ocr_output:
      )
      timeout = composer(client: FixtureClient.new(json_text: valid_json, error: Timeout::Error.new("Northstar timed out"))).call(
        inspection:,
        parser_output:,
        ocr_output:
      )
      oom = composer(client: FixtureClient.new(json_text: valid_json, error: QwenSemanticAdapter::OutOfMemory.new("INV-2026-1042 oom"))).call(
        inspection:,
        parser_output:,
        ocr_output:
      )
      corrupt = composer(client: FixtureClient.new(json_text: valid_json)).call(
        inspection:,
        parser_output: parser_output.merge(corrupt: true, text: "Northstar INV-2026-1042"),
        ocr_output:
      )

      assert invalid_json.needs_review?
      assert_equal Extraction::ProviderAdapter::JSON_INVALID, invalid_json.error_code
      assert timeout.failed?
      assert_equal SafeFailure::TIMEOUT, timeout.error_code
      assert oom.failed?
      assert_equal SafeFailure::OUT_OF_MEMORY, oom.error_code
      assert corrupt.quarantined?
      assert_equal SafeFailure::CORRUPT_DOCUMENT, corrupt.error_code

      [ invalid_json, timeout, oom, corrupt ].each do |result|
        serialized = result.to_h.to_s
        refute_includes serialized, "Northstar"
        refute_includes serialized, "INV-2026-1042"
        refute_includes serialized, valid_json
        assert_includes %w[failed quarantined needs_review], result.status
      end
    end

    private

    def composer(client:, cache: {})
      RouteComposer.new(
        semantic_adapter: QwenSemanticAdapter.new(
          client:,
          cache:,
          model_revision: "qwen3-vl-2026-06",
          quantization: "int4",
          runtime: "mlx",
          device: "apple-m4"
        )
      )
    end

    def inspection
      Intake::InspectionResult.new(
        status: "accepted",
        sha256: SOURCE_SHA256,
        byte_size: PDF_BYTES.bytesize,
        sniffed_mime_type: "application/pdf",
        declared_content_type: "application/pdf",
        filename: "invoice.pdf",
        detection: Intake::FormatDetection.new(
          family: "visual_pdf",
          route: "visual_model",
          profile: "local_visual_pdf",
          version: "m2-detection-v1",
          mvp_status: "supported"
        )
      )
    end

    def parser_output
      {
        version: "parser-fixture-v1",
        page_count: 1,
        pages: [
          {
            number: 1,
            width: 612,
            height: 792,
            layout_hash: "layout-page-1",
            text: "Northstar INV-2026-1042"
          }
        ]
      }
    end

    def ocr_output
      {
        version: "ocr-fixture-v1",
        page_count: 1,
        evidence: [
          {
            field_path: "/invoice/number",
            page: 1,
            bbox: [ 10, 10, 100, 20 ],
            text: "INV-2026-1042"
          }
        ]
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
