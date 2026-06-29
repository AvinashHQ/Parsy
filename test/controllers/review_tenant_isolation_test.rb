# frozen_string_literal: true

require "test_helper"
require "json"

class ReviewTenantIsolationTest < ActionDispatch::IntegrationTest
  FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

  setup do
    @tenant = Tenant.create!(name: "Alpha", slug: "alpha")
    @other_tenant = Tenant.create!(name: "Beta", slug: "beta")
    @user = User.create!(tenant: @tenant, email: "alpha@example.test", name: "Alpha User", operator_token: "alpha-token")
    @document = create_document(@tenant, "alpha-sha")
    @other_document = create_document(@other_tenant, "beta-sha")
    post session_path, params: { email: @user.email, operator_token: "alpha-token" }
  end

  test "tenant index hides other tenant batches" do
    get review_batches_path

    assert_response :success
    assert_includes response.body, @document.batch.name
    refute_includes response.body, @other_document.batch.name
  end

  test "cross tenant document access and mutation fail closed" do
    get review_document_path(@other_document)
    assert_response :not_found

    patch review_document_path(@other_document), params: { canonical_invoice: { invoice: { currency: "JPY" } } }
    assert_response :not_found
    assert_equal "EUR", @other_document.reload.current_revision.canonical_invoice.dig("invoice", "currency")

    post approve_review_document_path(@other_document), params: { confirm_blocking_findings: "true" }
    assert_response :not_found
    refute_equal "approved", @other_document.reload.status
  end

  test "cross tenant export is denied" do
    Review::ApprovalService.call(revision: @other_document.current_revision, actor: "beta@example.test")

    post review_batch_exports_path(@other_document.batch, format_type: "json")

    assert_response :not_found
    assert_equal 0, @other_document.batch.export_artifacts.count
  end

  test "same tenant export stores private artifact and serves short lived authenticated download" do
    Review::ApprovalService.call(revision: @document.current_revision, actor: @user.email)

    post review_batch_exports_path(@document.batch, format_type: "json")

    artifact = @document.batch.export_artifacts.last
    assert_redirected_to review_batch_export_download_path(@document.batch, artifact)
    assert artifact.file.attached?

    get review_batch_export_download_path(@document.batch, artifact)
    assert_response :success
    assert_includes response.headers.fetch("Cache-Control"), "private"
    assert_includes response.body, "doc_demo_global_0001"
  end

  private

  def create_document(tenant, source_sha)
    batch = Review::Batch.create!(tenant:, name: "#{tenant.slug} batch")
    Review::ProviderResultIngester.call(batch:, source_sha256: source_sha, result: result, source_metadata: { safe_preview_path: "preview://#{source_sha}" })
  end

  def result
    invoice = Canonical::Invoice.from_hash(invoice_hash)
    attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
      schema_version: "2.0", route: "visual_model", region: "global_generic_v1", provider: "fixture", provider_version: "m4", model: "fixture", model_version: "m4", prompt_sha256: "abc123", latency_ms: 1, repair_attempt: 0
    )
    Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) { def success? = true }.new(candidate: invoice, attempts: [ attempt ], idempotency_key: SecureRandom.hex(8))
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
