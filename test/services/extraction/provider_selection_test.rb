# frozen_string_literal: true

require "canonical_test_helper"

module Extraction
  class ProviderSelectionTest < Minitest::Test
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_001_minimal_visual_usd.json")
    SOURCE_SHA256 = "c7a72a7f3fc9f5c7209959fe15b7d29365ae0d4076d948f7b7a13f768d14fa36"
    EXPECTED_PROVIDER_REQUEST_KEYS = %i[
      model
      model_version
      prompt_id
      prompt_sha256
      provider_id
      provider_version
      region
      route
      schema_version
      source_sha256
    ].sort.freeze

    Provider = Struct.new(:json_text, :metadata, :calls, keyword_init: true) do
      def call(**request)
        calls << request
        {
          json_text: json_text,
          metadata: {
            provider_version: request.fetch(:provider_version),
            model: request.fetch(:model),
            model_version: request.fetch(:model_version),
            latency_ms: 3
          }
        }
      end
    end

    def test_fixture_local_and_existing_selection_preserve_provider_adapter_contract_and_canonical_schema
      service = selection(flags: { local_open_source: true })
      expected_attributes = Canonical::Invoice.from_json(valid_json).to_h

      %w[fixture local_open_source existing_provider].each do |provider_id|
        result = service.select(requested: provider_id)
        extraction = ProviderAdapter.new(provider: result.provider).extract(**base_request.merge(result.adapter_request))

        assert extraction.success?, provider_id
        assert_instance_of ProviderAdapter::Result, extraction
        assert_instance_of Canonical::Invoice, extraction.candidate
        assert_equal "2.0", extraction.candidate.schema_version
        assert_equal expected_attributes, extraction.attributes
        assert_empty Canonical::SchemaValidator.new.validate(extraction.attributes)
        assert_equal EXPECTED_PROVIDER_REQUEST_KEYS, result.provider.calls.last.keys.sort
        assert_equal %i[provider_id provider_version route], result.adapter_request.keys.sort
        assert_equal provider_id, result.metadata.fetch("selected_provider_id")
        assert_equal provider_id, result.metadata.fetch("route")
      end
    end

    def test_disabled_local_open_source_rolls_back_to_existing_provider_without_migration_state
      providers = provider_set
      service = selection(providers:, flags: { local_open_source: false })

      result = service.select(requested: "local_open_source")
      extraction = ProviderAdapter.new(provider: result.provider).extract(**base_request.merge(result.adapter_request))

      assert result.rolled_back
      assert result.existing_provider?
      refute result.local_open_source?
      assert_equal "existing_provider", result.selected.id
      assert_equal "local_open_source", result.metadata.fetch("requested_provider_id")
      assert_equal "existing_provider", result.metadata.fetch("selected_provider_id")
      assert_equal "existing-route-v1", result.selected.configuration_id
      assert_equal({ route: "existing_provider", provider_id: "managed-existing", provider_version: "existing-config-v1" }, result.adapter_request)
      assert extraction.success?
      assert_equal 1, providers.fetch(:existing_provider).calls.size
      assert_empty providers.fetch(:local_open_source).calls
    end

    def test_selection_metadata_is_immutable_content_free_and_config_like
      result = selection(flags: { local_open_source: true }).select(requested: "local_open_source")
      metadata = result.metadata

      assert metadata.frozen?
      assert result.adapter_request.frozen?
      assert_raises(FrozenError) { metadata["route"] = "changed" }
      assert_raises(FrozenError) { result.adapter_request[:route] = "changed" }
      assert_equal "local-route-v1", metadata.fetch("configuration_id")
      assert_equal "local-semantic", metadata.fetch("adapter_provider_id")
      assert_equal "local-config-v1", metadata.fetch("adapter_provider_version")
      assert_equal false, metadata.key?("raw_response_body")
      assert_equal false, metadata.key?("source_text")
      assert_equal false, metadata.key?("signed_url")

      serialized_metadata = metadata.to_s
      refute_includes serialized_metadata, valid_json
      refute_includes serialized_metadata, "Northstar"
      refute_includes serialized_metadata, "INV-2026-1042"
      assert metadata.values.all? { |value| value.is_a?(String) || value == true || value == false || value.nil? }
    end

    def test_tenant_flag_can_enable_local_open_source_without_changing_available_provider_shape
      service = selection(flags: { local_open_source: false })

      disabled = service.select(requested: "local_open_source")
      enabled = service.select(requested: "local_open_source", tenant_flags: { local_open_source: true })

      assert disabled.rolled_back
      assert disabled.existing_provider?
      refute enabled.rolled_back
      assert enabled.local_open_source?
      assert_equal [ "existing_provider", "fixture", "local_open_source" ], enabled.available.map(&:id).sort
      assert_equal [ "adapter_request", "configuration_id", "enabled", "id", "metadata", "route" ], enabled.selected.to_h.keys.map(&:to_s).sort
    end

    private

    def selection(providers: provider_set, flags: {})
      ProviderSelection.new(providers:, flags:, configurations: provider_configurations)
    end

    def provider_set
      {
        existing_provider: provider_with_sensitive_metadata,
        fixture: provider_with_sensitive_metadata,
        local_open_source: provider_with_sensitive_metadata
      }
    end

    def provider_with_sensitive_metadata
      Provider.new(
        json_text: valid_json,
        metadata: {
          raw_response_body: valid_json,
          source_text: "Northstar Services Ltd INV-2026-1042",
          signed_url: "https://example.invalid/secret",
          arbitrary_note: "must not be selected metadata"
        },
        calls: []
      )
    end

    def provider_configurations
      {
        existing_provider: {
          route: "existing_provider",
          configuration_id: "existing-route-v1",
          adapter_provider_id: "managed-existing",
          adapter_provider_version: "existing-config-v1"
        },
        fixture: {
          route: "fixture",
          configuration_id: "fixture-route-v1",
          adapter_provider_id: "fixture-provider",
          adapter_provider_version: "fixture-config-v1"
        },
        local_open_source: {
          route: "local_open_source",
          configuration_id: "local-route-v1",
          adapter_provider_id: "local-semantic",
          adapter_provider_version: "local-config-v1"
        }
      }
    end

    def base_request
      {
        source_sha256: SOURCE_SHA256,
        region: "US",
        schema_version: "2.0",
        prompt_id: "extract_invoice_v2",
        model: "contract-test-model",
        model_version: "contract-test-revision"
      }
    end

    def valid_json
      FIXTURE_PATH.read
    end
  end
end
