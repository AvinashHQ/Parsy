# frozen_string_literal: true

require "test_helper"
require "stringio"
require "json"

module Retention
  class PurgeBatchTest < ActiveSupport::TestCase
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    test "purge removes private object classes and records evidence" do
      tenant = Tenant.create!(name: "Retention", slug: "retention")
      batch = Review::Batch.create!(tenant:, name: "Retention batch")
      document = Review::ProviderResultIngester.call(batch:, source_sha256: "retention-sha", result: result, source_metadata: { safe_preview_path: "preview://retention" })
      document.source_file.attach(io: StringIO.new("private invoice bytes"), filename: "invoice.pdf", content_type: "application/pdf", identify: false)
      Review::ApprovalService.call(revision: document.current_revision, actor: "operator@example.test")
      artifact, = Review::ApprovedRevisionExporter.call(batch:, format: "json", actor: "operator@example.test")

      assert document.source_file.attached?
      assert artifact.file.attached?

      Retention::PurgeBatch.call(batch:, actor: "operator@example.test")

      assert_equal "purged", batch.reload.status
      assert_equal "purged", document.reload.status
      assert_not document.source_file.attached?
      assert_not artifact.reload.file.attached?
      evidence = Retention::PurgeEvidence.find_by!(batch:)
      assert_equal "purged", evidence.status
      assert_equal 1, evidence.object_counts.fetch("source_files")
      assert_equal 1, evidence.object_counts.fetch("export_files")
      assert Retention::ReconcileObjects.call(batch:).clean?
    end

    private

    def result
      invoice = Canonical::Invoice.from_hash(invoice_hash)
      attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
        schema_version: "2.0", route: "visual_model", region: "global_generic_v1", provider: "fixture", provider_version: "m4", model: "fixture", model_version: "m4", prompt_sha256: "abc123", latency_ms: 1, repair_attempt: 0
      )
      Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) { def success? = true }.new(candidate: invoice, attempts: [ attempt ], idempotency_key: "retention")
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
