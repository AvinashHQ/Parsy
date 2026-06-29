# frozen_string_literal: true

require "test_helper"
require "json"

module Operations
  class RestoreVerifierTest < ActiveSupport::TestCase
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    test "restore verifier checks tenant batches revisions and object reconciliation" do
      tenant = Tenant.create!(name: "Restore", slug: "restore")
      batch = Review::Batch.create!(tenant:, name: "Restored batch")
      document = Review::ProviderResultIngester.call(batch:, source_sha256: "restore-sha", result: result, source_metadata: {})
      Review::ApprovalService.call(revision: document.current_revision, actor: "operator@example.test")

      verification = Operations::RestoreVerifier.call(tenant:)

      assert verification.ok
      assert_equal 1, verification.checked.fetch(:batches)
      assert_empty verification.errors
    end

    private

    def result
      invoice = Canonical::Invoice.from_hash(invoice_hash)
      attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
        schema_version: "2.0", route: "visual_model", region: "global_generic_v1", provider: "fixture", provider_version: "m4", model: "fixture", model_version: "m4", prompt_sha256: "abc123", latency_ms: 1, repair_attempt: 0
      )
      Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) { def success? = true }.new(candidate: invoice, attempts: [ attempt ], idempotency_key: "restore")
    end

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
