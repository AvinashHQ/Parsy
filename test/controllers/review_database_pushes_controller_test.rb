# frozen_string_literal: true

require "test_helper"
require "json"

class ReviewDatabasePushesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  FIXTURE = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

  SNAPSHOT = {
    "tables" => [
      { "name" => "customer_invoices", "columns" => [
        { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => true }
      ] }
    ]
  }.freeze

  setup do
    @tenant = Tenant.create!(name: "Push Alpha", slug: "push-alpha")
    @other_tenant = Tenant.create!(name: "Push Beta", slug: "push-beta")
    @user = User.create!(tenant: @tenant, email: "push@example.test", name: "Push User", operator_token: "push-token")
    @batch = Review::Batch.create!(tenant: @tenant, name: "Push batch")
    @document = ingest_document!(@batch)
    @connection = create_destination!(@tenant)
    post session_path, params: { email: @user.email, operator_token: "push-token" }
  end

  test "create enqueues a pending push for approved documents" do
    approve!

    assert_difference -> { Destination::Push.count }, 1 do
      assert_enqueued_with(job: Destination::PushBatchJob) do
        post review_batch_database_pushes_path(@batch), params: { destination_connection_id: @connection.id }
      end
    end

    push = Destination::Push.last
    assert_equal "pending", push.status
    assert_equal @user.email, push.actor
    assert_equal @connection, push.database_connection
    assert_redirected_to review_batch_path(@batch)
  end

  test "create refuses without approved documents" do
    assert_no_difference -> { Destination::Push.count } do
      post review_batch_database_pushes_path(@batch), params: { destination_connection_id: @connection.id }
    end

    assert_redirected_to review_batch_path(@batch)
    follow_redirect!
    assert_includes response.body, "No approved documents"
  end

  test "create refuses without a confirmed invoices mapping" do
    approve!
    @connection.field_mappings.sole.update!(status: "proposed")

    assert_no_difference -> { Destination::Push.count } do
      post review_batch_database_pushes_path(@batch), params: { destination_connection_id: @connection.id }
    end

    follow_redirect!
    assert_includes response.body, "no confirmed invoices mapping"
  end

  test "retry re-enqueues only failed documents" do
    approve!
    push = Destination::Push.create!(
      tenant: @tenant, batch: @batch, database_connection: @connection, actor: @user.email,
      status: "partial",
      document_results: {
        @document.id.to_s => { "status" => "failed", "operation" => "write_failed", "issues" => [] },
        "999999" => { "status" => "pushed", "operation" => "inserted", "issues" => [] }
      }
    )

    assert_enqueued_with(job: Destination::PushBatchJob, args: [ push.id, { document_ids: [ @document.id ] } ]) do
      post retry_review_batch_database_push_path(@batch, push)
    end
    assert_redirected_to review_batch_path(@batch)
  end

  test "retry with nothing failed is refused" do
    push = Destination::Push.create!(
      tenant: @tenant, batch: @batch, database_connection: @connection, actor: @user.email,
      status: "pushed", document_results: { @document.id.to_s => { "status" => "pushed", "operation" => "inserted" } }
    )

    assert_no_enqueued_jobs only: Destination::PushBatchJob do
      post retry_review_batch_database_push_path(@batch, push)
    end
    follow_redirect!
    assert_includes response.body, "Nothing to retry"
  end

  test "cross-tenant batches, destinations, and pushes fail closed" do
    approve!
    other_batch = Review::Batch.create!(tenant: @other_tenant, name: "Beta batch")
    other_connection = create_destination!(@other_tenant, label: "beta-live")
    other_push = Destination::Push.create!(tenant: @other_tenant, batch: other_batch, database_connection: other_connection, actor: "beta@example.test")

    post review_batch_database_pushes_path(other_batch), params: { destination_connection_id: other_connection.id }
    assert_response :not_found

    post review_batch_database_pushes_path(@batch), params: { destination_connection_id: other_connection.id }
    assert_response :not_found

    post retry_review_batch_database_push_path(other_batch, other_push)
    assert_response :not_found
  end

  test "batch page renders the push panel with history" do
    approve!
    Destination::Push.create!(
      tenant: @tenant, batch: @batch, database_connection: @connection, actor: @user.email,
      status: "partial", pushed_count: 1, failed_count: 1,
      document_results: { @document.id.to_s => { "status" => "failed", "operation" => "write_failed", "issues" => [ { "code" => "write_failed" } ] } }
    )

    get review_batch_path(@batch)

    assert_response :success
    assert_includes response.body, "Push to database"
    assert_includes response.body, @connection.label
    assert_includes response.body, "Retry failed"
    assert_includes response.body, "1 failed document"
  end

  private

  def approve!
    Review::ApprovalService.call(revision: @document.current_revision, actor: @user.email)
  end

  def ingest_document!(batch)
    attributes = JSON.parse(FIXTURE.read)
    attributes["evidence"] += [
      { "field_path" => "/supplier/display_name", "source_kind" => "visual", "page" => 1, "text" => "Northstar Services Ltd", "source_path" => nil, "bbox" => nil },
      { "field_path" => "/invoice/currency", "source_kind" => "visual", "page" => 1, "text" => "EUR", "source_path" => nil, "bbox" => nil }
    ]
    invoice = Canonical::Invoice.from_hash(attributes)
    attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
      schema_version: "2.0", route: "visual_model", region: "global_generic_v1", provider: "fixture",
      provider_version: "m4", model: "fixture", model_version: "m4", prompt_sha256: "abc123", latency_ms: 1, repair_attempt: 0
    )
    result = Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) { def success? = true }
                   .new(candidate: invoice, attempts: [ attempt ], idempotency_key: SecureRandom.hex(8))
    Review::ProviderResultIngester.call(batch:, source_sha256: SecureRandom.hex(8), result:, source_metadata: { safe_preview_path: "preview://test" })
  end

  def create_destination!(tenant, label: "live")
    connection = Destination::DatabaseConnection.create!(
      tenant: tenant, label: label, adapter: "postgresql", host: "db.customer.example", port: 5432,
      database_name: "erp", username: "writer", password: "secret-value", ssl_mode: "prefer",
      schema_snapshot: SNAPSHOT, schema_captured_at: Time.current
    )
    Destination::FieldMapping.create!(
      tenant: tenant, database_connection: connection, source_table: "invoices",
      target_table: "customer_invoices", status: "confirmed",
      column_mappings: [ { "source_column" => "document_id", "target_column" => "doc_ref" } ]
    )
    connection
  end
end
