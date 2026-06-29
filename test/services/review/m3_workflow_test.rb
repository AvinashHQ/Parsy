# frozen_string_literal: true

require "test_helper"
require "json"

module Review
  class M3WorkflowTest < ActiveSupport::TestCase
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    Attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true)
    Result = Struct.new(:candidate, :attempts, :idempotency_key, :error_code, keyword_init: true) do
      def success? = candidate.present?
    end

    class LocalFixtureClient
      attr_reader :extract_requests

      def initialize(json_text:)
        @json_text = json_text
        @extract_requests = []
      end

      def extract_invoice(request)
        extract_requests << request
        { json_text: @json_text, metadata: { latency_ms: 17 } }
      end

      def repair_invoice(_request)
        { patch: {} }
      end

      private

      attr_reader :json_text
    end

    test "ingests M2_5 output into persisted review workflow and risk queue" do
      batch = Review::Batch.create!(name: "M3 fixture batch")
      document = Review::ProviderResultIngester.call(batch: batch, source_sha256: "sha-review-1", result: result(candidate: invoice_missing_evidence), source_metadata: { filename: "supplier.pdf", mime_type: "application/pdf", page_count: 1, safe_preview_path: "preview://sha-review-1" })

      assert_equal "review", batch.reload.status
      assert_equal "needs_review", document.status
      assert_equal "visual_model", document.route
      assert_equal "en-GB", document.detected_language
      assert_equal "EUR", document.detected_currency
      assert_equal "global_generic_v1", document.rule_pack_id
      assert_equal 1, document.candidate_revisions.count
      assert_equal 3, document.current_revision.evidence_references.count
      assert document.findings.unresolved.blocking.exists?(code: "HIGH_RISK_EVIDENCE_MISSING")
      assert_operator document.reload.risk_score, :>, 0
      assert_equal [ document ], Review::RiskQueue.call(batch).to_a
    end

    test "acceptance blocks unresolved high findings until explicit operator confirmation" do
      batch = Review::Batch.create!(name: "M3 approval batch")
      document = Review::ProviderResultIngester.call(batch: batch, source_sha256: "sha-review-2", result: result(candidate: invoice_missing_evidence))
      revision = document.current_revision

      assert_not Review::AcceptancePolicy.new(revision).auto_acceptable?
      assert_raises Review::ApprovalService::ConfirmationRequired do
        Review::ApprovalService.call(revision: revision, actor: "ap-operator", confirmation: false)
      end

      Review::ApprovalService.call(revision: revision, actor: "ap-operator", confirmation: true, reason: "source reviewed")

      assert revision.reload.approved?
      assert_equal "ap-operator", revision.approved_by
      assert_equal "approved", document.reload.status
      assert_equal revision, document.approved_revision
      assert_empty revision.findings.unresolved.blocking
      assert document.events.exists?(action: "approved_with_confirmation")
      assert_raises(ActiveRecord::ReadOnlyRecord) { revision.update!(canonical_invoice: invoice_complete_evidence.to_h) }
    end

    test "editor creates new revision, records overrides, and revalidates changed invoice" do
      batch = Review::Batch.create!(name: "M3 edit batch")
      document = Review::ProviderResultIngester.call(batch: batch, source_sha256: "sha-review-3", result: result(candidate: invoice_complete_evidence))
      original = document.current_revision

      edited = Review::RevisionEditor.call(
        revision: original,
        patch: { invoice: { currency: "JPY" }, totals: { payable_amount: "1200.55" } },
        overrides: { document_language: "ja-JP", supplier_country: "JP", currency: "JPY", source_format_family: "visual_pdf", source_format_profile: "local_visual_pdf", rule_pack_id: "global_generic_v1", rule_pack_version: "1.0.1" },
        actor: "ap-operator",
        reason: "operator locale correction"
      )

      assert_equal "superseded", original.reload.status
      assert_equal edited, document.reload.current_revision
      assert_includes edited.changed_field_paths, "/invoice/currency"
      assert_includes edited.changed_field_paths, "/totals/payable_amount"
      assert_equal "ja-JP", edited.locale_overrides.fetch("document_language")
      assert_equal "ja-JP", document.detected_language
      assert_equal "JP", document.detected_country
      assert_equal "JPY", document.detected_currency
      assert_equal "local_visual_pdf", document.source_format_profile
      assert_equal "1.0.1", document.rule_pack_version
      assert edited.findings.exists?(code: "CURRENCY_PRECISION_MISMATCH")
      event = document.events.find_by!(action: "revision_edited")
      assert_equal [ "/invoice/currency", "/totals/payable_amount" ].sort, event.changed_field_paths.sort
      assert event.old_value_hash.present?
      assert event.new_value_hash.present?
    end

    test "exporter emits only approved immutable revisions" do
      batch = Review::Batch.create!(name: "M3 export batch")
      document = Review::ProviderResultIngester.call(batch: batch, source_sha256: "sha-review-4", result: result(candidate: invoice_complete_evidence))

      assert_raises Canonical::Exports::ExportService::UnapprovedRevision do
        Review::ApprovedRevisionExporter.call(batch: batch, format: "json", actor: "ap-operator")
      end

      Review::ApprovalService.call(revision: document.current_revision, actor: "ap-operator")
      artifact, payload = Review::ApprovedRevisionExporter.call(batch: batch, format: "json", actor: "ap-operator")

      assert_equal "json", artifact.format
      assert_equal [ document.current_revision.id ], artifact.approved_revision_ids
      assert_includes payload, "doc_demo_global_0001"
      assert_equal "exported", document.reload.status
      assert_equal "exported", batch.reload.status
    end

    test "provider result ingestion and review job are idempotent" do
      batch = Review::Batch.create!(name: "M3 idempotency batch")
      source_sha = "sha-review-idempotent"
      local_result = m2_5_result(source_sha:)

      document = Review::ProviderResultIngester.call(batch: batch, source_sha256: source_sha, result: local_result, source_metadata: source_metadata(source_sha))
      repeated = Review::ProviderResultIngester.call(batch: batch, source_sha256: source_sha, result: local_result, source_metadata: source_metadata(source_sha))

      assert_equal document.id, repeated.id
      assert_equal 1, batch.documents.count
      assert_equal 1, document.reload.candidate_revisions.count
      assert_equal 1, document.events.where(action: "candidate_created").count
      assert_equal 1, document.events.where(action: "candidate_reused").count

      Review::ProcessDocumentJob.perform_now(document.id)
      assert_equal "ready_for_approval", document.reload.status

      Review::ApprovalService.call(revision: document.current_revision, actor: "ap-operator")
      Review::ProcessDocumentJob.perform_now(document.id)

      assert_equal "approved", document.reload.status
      assert_equal 1, document.candidate_revisions.count
    end


    test "operator completes a fifty document batch from M2_5 route output" do
      batch = Review::Batch.create!(name: "M3 50 document exit gate")

      50.times do |index|
        source_sha = "sha-review-50-#{index}"
        document = Review::ProviderResultIngester.call(batch: batch, source_sha256: source_sha, result: m2_5_result(source_sha:), source_metadata: source_metadata(source_sha))
        Review::ApprovalService.call(revision: document.current_revision, actor: "ap-operator")
      end

      progress = Review::BatchProgress.call(batch.reload)
      assert_equal 50, progress[:total]
      assert_equal 50, progress[:completed]
      assert_equal 100, progress[:percent]
      assert_equal "completed", batch.status
      assert_empty batch.documents.joins(:findings).merge(Review::ValidationFinding.unresolved.blocking)
      assert_equal 50, batch.documents.where(status: "approved").count
      assert_equal 50, batch.documents.joins(:approved_revision).where(candidate_revisions: { status: "approved" }).count
    end

    private

    def m2_5_result(source_sha:)
      composer.call(inspection: inspection(source_sha:), parser_output: parser_output, ocr_output: ocr_output)
    end

    def composer
      LocalExtraction::RouteComposer.new(
        semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(
          client: LocalFixtureClient.new(json_text: JSON.generate(invoice_complete_evidence.to_h)),
          cache: {},
          model_revision: "qwen3-vl-2026-06",
          quantization: "int4",
          runtime: "mlx",
          device: "apple-m4"
        )
      )
    end

    def inspection(source_sha:)
      Intake::InspectionResult.new(
        status: "accepted",
        sha256: source_sha,
        byte_size: 128,
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
        pages: [ { number: 1, width: 612, height: 792, layout_hash: "layout-page-1", text: "Northstar INV-2026-1042" } ]
      }
    end

    def ocr_output
      {
        version: "ocr-fixture-v1",
        page_count: 1,
        evidence: [ { field_path: "/invoice/number", page: 1, bbox: [ 10, 10, 100, 20 ], text: "INV-2026-1042" } ]
      }
    end

    def source_metadata(source_sha)
      { filename: "#{source_sha}.pdf", mime_type: "application/pdf", page_count: 1, safe_preview_path: "preview://#{source_sha}" }
    end

    def result(candidate:)
      Result.new(
        candidate: candidate,
        attempts: [ Attempt.new(schema_version: "2.0", route: "visual_model", region: "global_generic_v1", provider: "fixture", provider_version: "m3", model: "fixture", model_version: "m3", prompt_sha256: "abc123", latency_ms: 15, repair_attempt: 0) ],
        idempotency_key: "m3-#{candidate.document_id}"
      )
    end

    def invoice_missing_evidence
      Canonical::Invoice.from_hash(base_invoice_hash)
    end

    def invoice_complete_evidence
      attributes = base_invoice_hash
      attributes["evidence"] += [
        { "field_path" => "/supplier/display_name", "source_kind" => "visual", "page" => 1, "text" => "Northstar Services Ltd", "source_path" => nil, "bbox" => nil },
        { "field_path" => "/invoice/currency", "source_kind" => "visual", "page" => 1, "text" => "EUR", "source_path" => nil, "bbox" => nil }
      ]
      Canonical::Invoice.from_hash(attributes)
    end

    def base_invoice_hash
      JSON.parse(FIXTURE_PATH.read)
    end
  end
end
