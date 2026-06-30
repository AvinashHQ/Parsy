# frozen_string_literal: true

require "test_helper"

class ReviewExtractionControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @tenant = Tenant.create!(name: "Extract Tenant", slug: "extract-#{SecureRandom.hex(4)}")
    @user = User.create!(tenant: @tenant, email: "op@example.test", name: "Op", operator_token: "extract-token")
    @batch = @tenant.review_batches.create!(name: "Extraction Batch")
    @document = @batch.documents.create!(source_sha256: "ctrl-sha", status: "needs_review", route: "visual_model")
    post session_path, params: { email: @user.email, operator_token: "extract-token" }
  end

  test "extract enqueues a forced extraction job and marks the document extracting" do
    assert_enqueued_with(job: Review::ProcessDocumentJob) do
      post extract_review_document_path(@document)
    end

    assert_redirected_to review_document_path(@document)
    assert_equal "extracting", @document.reload.status
    assert_equal 1, @document.events.where(action: "extraction_requested").count
  end

  test "extract is tenant-scoped and fails closed for other tenants" do
    other = Tenant.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    other_doc = other.review_batches.create!(name: "Other Batch").documents.create!(source_sha256: "other-sha", status: "needs_review")

    post extract_review_document_path(other_doc)

    assert_response :not_found
  end

  test "no-candidate review page shows graceful processing components" do
    get review_document_path(@document)

    assert_response :success
    assert_select "section[aria-label='Extraction status']"
    assert_select "section[aria-label='Source and profile']"
    assert_select "section[aria-label='Processing timeline']"
    assert_select "form[action='#{extract_review_document_path(@document)}']"
    assert_includes response.body, "No candidate revision available"
  end
end
