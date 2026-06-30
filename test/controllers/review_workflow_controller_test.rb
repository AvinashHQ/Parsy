# frozen_string_literal: true

require "test_helper"
require "json"

class ReviewWorkflowControllerTest < ActionDispatch::IntegrationTest
  FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

  setup do
    @tenant = Tenant.create!(name: "Controller Tenant", slug: "controller-tenant")
    @user = User.create!(tenant: @tenant, email: "operator@example.test", name: "Operator", operator_token: "controller-token")
    post session_path, params: { email: @user.email, operator_token: "controller-token" }
  end

  def test_batch_and_document_review_screens_show_m3_controls
    document = create_review_document

    get review_batch_path(document.batch)
    assert_response :success
    assert_select "section[aria-label='Batch progress']"
    assert_select "section[aria-label='Risk-ranked review queue']"
    assert_select "form[action='#{review_batch_exports_path(document.batch, format_type: 'json')}']"

    get review_document_path(document)
    assert_response :success
    assert_select "section[aria-label='Source and profile']"
    assert_select "section[aria-label='Validation findings']"
    assert_select "section[aria-label='Evidence references']"
    assert_select "section[aria-label='Canonical editor']"
    assert_select "li#evidence-invoice-number[tabindex='-1']"
    assert_select "input[name='canonical_invoice[invoice][number]'][aria-describedby='evidence-invoice-number'][data-evidence-id-param='evidence-invoice-number']"
    assert_select "button[accesskey='s']"
    assert_select "form[action='#{approve_review_document_path(document)}'] button[accesskey='a']"
    assert_select "form[action='#{reject_review_document_path(document)}'] button[accesskey='r']"
  end

  def test_controller_save_and_approve_use_persisted_revisions_without_provider_calls
    document = create_review_document
    forbid_provider_calls do
      patch review_document_path(document), params: {
        canonical_invoice: { invoice: { currency: "JPY" } },
        overrides: { document_language: "ja-JP", supplier_country: "JP", currency: "JPY", source_format_family: "visual_pdf", source_format_profile: "local_visual_pdf", rule_pack_id: "global_generic_v1", rule_pack_version: "1.0.1" },
        reason: "operator override"
      }
      assert_redirected_to review_document_path(document)

      assert_equal "JPY", document.reload.current_revision.canonical_invoice.dig("invoice", "currency")
      assert_equal "ja-JP", document.current_revision.locale_overrides.fetch("document_language")
      assert_equal "ja-JP", document.detected_language
      assert_equal "JP", document.detected_country
      assert_equal "JPY", document.detected_currency
      assert_equal "local_visual_pdf", document.source_format_profile
      assert_equal "1.0.1", document.rule_pack_version

      post approve_review_document_path(document), params: { confirm_blocking_findings: "true", reason: "operator confirmed" }
      assert_response :redirect
      assert_equal "approved", document.reload.status
    end
  end

  private

  def create_review_document
    batch = Review::Batch.create!(tenant: @tenant, name: "Controller batch")
    invoice = Canonical::Invoice.from_hash(invoice_hash)
    result = Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) do
      def success? = true
    end.new(candidate: invoice, attempts: [ attempt ], idempotency_key: "controller-m3")
    Review::ProviderResultIngester.call(batch: batch, source_sha256: "controller-sha-#{SecureRandom.hex(4)}", result: result, source_metadata: { safe_preview_path: "preview://controller" })
  end

  def attempt
    Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
      schema_version: "2.0",
      route: "visual_model",
      region: "global_generic_v1",
      provider: "fixture",
      provider_version: "m3",
      model: "fixture",
      model_version: "m3",
      prompt_sha256: "abc123",
      latency_ms: 1,
      repair_attempt: 0
    )
  end

  def invoice_hash
    attributes = JSON.parse(FIXTURE_PATH.read)
    attributes["evidence"] += [
      { "field_path" => "/supplier/display_name", "source_kind" => "visual", "page" => 1, "text" => "Northstar Services Ltd", "source_path" => nil, "bbox" => nil },
      { "field_path" => "/invoice/currency", "source_kind" => "visual", "page" => 1, "text" => "EUR", "source_path" => nil, "bbox" => nil }
    ]
    attributes
  end

  def forbid_provider_calls
    original = Extraction::ProviderAdapter.instance_method(:extract)
    Extraction::ProviderAdapter.define_method(:extract) do |*|
      raise "controllers must not call extraction providers"
    end
    yield
  ensure
    Extraction::ProviderAdapter.define_method(:extract, original)
  end
end
