# frozen_string_literal: true

require "application_system_test_case"
require "json"

class ReviewKeyboardFlowTest < ApplicationSystemTestCase
  FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

  class LocalFixtureClient
    def initialize(json_text:)
      @json_text = json_text
    end

    def extract_invoice(_request)
      { json_text: @json_text, metadata: { latency_ms: 17 } }
    end

    def repair_invoice(_request)
      { patch: {} }
    end
  end

  setup do
    @tenant = Tenant.create!(name: "System Tenant", slug: "system-tenant")
    @user = User.create!(tenant: @tenant, email: "system-operator@example.test", name: "System Operator", operator_token: "system-token")
    visit new_session_path
    fill_in "Email", with: @user.email
    fill_in "Operator token", with: "system-token"
    click_on "Sign in"
  end

  test "operator completes fifty document M2_5 review flow with keyboard controls" do
    batch = Review::Batch.create!(tenant: @tenant, name: "M3 keyboard exit batch")

    50.times do |index|
      source_sha = "system-m3-#{index}"
      Review::ProviderResultIngester.call(
        batch: batch,
        source_sha256: source_sha,
        result: m2_5_result(source_sha:),
        source_metadata: source_metadata(source_sha)
      )
    end

    visit review_batch_path(batch)
    assert_selector "section[aria-label='Batch progress']", text: "0 / 50 complete (0%)"
    assert_selector "section[aria-label='Risk-ranked review queue'] a[accesskey='n']", count: 50

    50.times do
      document = Review::RiskQueue.call(batch.reload).first
      visit review_document_path(document)

      assert_selector "input[name='canonical_invoice[invoice][number]'][aria-describedby='evidence-invoice-number']"
      assert_selector "input[accesskey='s']"
      assert_selector "tr#evidence-invoice-number[tabindex='-1']"
      find("button[accesskey='a']").send_keys(:enter)
      assert_text "Approved document"
    end

    visit review_batch_path(batch.reload)
    assert_selector "section[aria-label='Batch progress']", text: "50 / 50 complete (100%)"
    assert_equal "completed", batch.reload.status
    assert_equal 50, batch.documents.where(status: "approved").count
    assert_empty batch.documents.joins(:findings).merge(Review::ValidationFinding.unresolved.blocking)
  end

  private

  def m2_5_result(source_sha:)
    composer.call(inspection: inspection(source_sha:), parser_output: parser_output, ocr_output: ocr_output)
  end

  def composer
    LocalExtraction::RouteComposer.new(
      semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(
        client: LocalFixtureClient.new(json_text: JSON.generate(invoice_hash)),
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

  def invoice_hash
    attributes = JSON.parse(FIXTURE_PATH.read)
    attributes["evidence"] += [
      { "field_path" => "/supplier/display_name", "source_kind" => "visual", "page" => 1, "text" => "Northstar Services Ltd", "source_path" => nil, "bbox" => nil },
      { "field_path" => "/invoice/currency", "source_kind" => "visual", "page" => 1, "text" => "EUR", "source_path" => nil, "bbox" => nil }
    ]
    attributes
  end
end
