# frozen_string_literal: true

require "test_helper"
require "json"

module Usage
  class SpendGuardTest < ActiveSupport::TestCase
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    class CountingProvider
      attr_reader :calls

      def initialize(json_text)
        @json_text = json_text
        @calls = 0
      end

      def call(**)
        @calls += 1
        { json_text: @json_text, metadata: { cost: 75, latency_ms: 1 } }
      end
    end

    test "spend guard opens circuit breaker at ceiling" do
      tenant = Tenant.create!(name: "Quota", slug: "quota", monthly_spend_limit_cents: 50)
      result = Usage::SpendGuard.reserve!(tenant:, provider: "qwen", estimated_cents: 75, idempotency_key: "quota-1")

      assert_not result.allowed
      assert_equal Usage::SpendGuard::COST_LIMIT_PAUSED, result.error_code
      assert_equal "open", tenant.reload.circuit_breaker_status
      assert_equal "paused", tenant.usage_spend_events.last.status
    end

    test "provider adapter does not call provider when quota is paused" do
      tenant = Tenant.create!(name: "Adapter Quota", slug: "adapter-quota", monthly_spend_limit_cents: 10)
      provider = CountingProvider.new(JSON.generate(invoice_hash))
      adapter = Extraction::ProviderAdapter.new(provider:, quota_guard: Usage::SpendGuard.new(tenant:))

      result = adapter.extract(source_sha256: "quota-sha", route: "visual_model", provider_id: "fixture", prompt_id: "quota", estimated_cost_cents: 25)

      assert result.rejected?
      assert_equal Extraction::ProviderAdapter::COST_LIMIT_PAUSED, result.error_code
      assert_equal 0, provider.calls
      assert_equal "open", tenant.reload.circuit_breaker_status
    end

    private

    def invoice_hash
      attributes = JSON.parse(FIXTURE_PATH.read)
      attributes["evidence"] += [
        { "field_path" => "/supplier/display_name", "source_kind" => "visual", "page" => 1, "text" => "Northstar Services Ltd", "source_path" => nil, "bbox" => nil },
        { "field_path" => "/invoice/currency", "source_kind" => "visual", "page" => 1, "text" => "EUR", "source_path" => nil, "bbox" => nil }
      ]
      attributes
    end
  end
end
