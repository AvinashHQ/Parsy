# frozen_string_literal: true

require "test_helper"

class DestinationsMappingsControllerTest < ActionDispatch::IntegrationTest
  SNAPSHOT = {
    "tables" => [
      {
        "name" => "customer_invoices",
        "columns" => [
          { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => true },
          { "name" => "inv_no", "data_type" => "character varying", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
          { "name" => "grand_total", "data_type" => "numeric", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
          { "name" => "issued_on", "data_type" => "date", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
        ]
      }
    ]
  }.freeze

  setup do
    # allowed_providers excludes google_gemini so proposals stay heuristic-only in tests.
    @tenant = Tenant.create!(name: "Map Alpha", slug: "map-alpha", allowed_providers: [ "fixture" ])
    @other_tenant = Tenant.create!(name: "Map Beta", slug: "map-beta", allowed_providers: [ "fixture" ])
    @user = User.create!(tenant: @tenant, email: "map@example.test", name: "Map User", operator_token: "map-token")
    @connection = create_connection!(tenant: @tenant)
    post session_path, params: { email: @user.email, operator_token: "map-token" }
  end

  test "propose derives a mapping from the captured schema" do
    assert_difference -> { Destination::FieldMapping.count }, 1 do
      post propose_destinations_connection_mappings_path(@connection), params: { source_table: "invoices" }
    end

    mapping = Destination::FieldMapping.last
    assert_equal "customer_invoices", mapping.target_table
    assert_equal "proposed", mapping.status
    assert_equal "inv_no", mapping.target_column_for("invoice_number")
    assert_redirected_to edit_destinations_connection_mapping_path(@connection, mapping)
  end

  test "propose without a captured schema explains what to do" do
    bare = create_connection!(tenant: @tenant, label: "bare", snapshot: {})

    post propose_destinations_connection_mappings_path(bare), params: { source_table: "invoices" }

    assert_redirected_to destinations_connection_path(bare)
    follow_redirect!
    assert_includes response.body, "introspect the destination schema"
  end

  test "edit renders the column editor with the validation report" do
    mapping = propose!

    get edit_destinations_connection_mapping_path(@connection, mapping)

    assert_response :success
    assert_includes response.body, "Column mapping editor"
    assert_includes response.body, "mappings[invoice_number]"
    assert_includes response.body, "idempotent push key"
  end

  test "update rewrites the mapping as operator-owned and resets confirmation" do
    mapping = propose!
    mapping.update!(column_mappings: [ { "source_column" => "document_id", "target_column" => "doc_ref" } ], status: "confirmed")

    patch destinations_connection_mapping_path(@connection, mapping), params: { mappings: {
      "document_id" => "doc_ref", "invoice_number" => "inv_no", "payable_amount" => "grand_total", "supplier_name" => ""
    } }

    mapping.reload
    assert_equal "operator", mapping.origin
    assert_equal "proposed", mapping.status
    assert_equal "grand_total", mapping.target_column_for("payable_amount")
    assert_nil mapping.target_column_for("supplier_name")
  end

  test "confirm gates on the validation report" do
    mapping = propose!
    mapping.update!(column_mappings: [ { "source_column" => "invoice_number", "target_column" => "inv_no" } ])

    post confirm_destinations_connection_mapping_path(@connection, mapping)
    assert_equal "invalid", mapping.reload.status

    mapping.update!(column_mappings: [ { "source_column" => "document_id", "target_column" => "doc_ref" } ])
    post confirm_destinations_connection_mapping_path(@connection, mapping)

    assert_equal "confirmed", mapping.reload.status
    assert_redirected_to destinations_connection_path(@connection)
  end

  test "cross-tenant mapping access fails closed" do
    other_connection = create_connection!(tenant: @other_tenant, label: "beta-conn")
    other_mapping = Destination::FieldMapping.create!(
      tenant: @other_tenant, database_connection: other_connection,
      source_table: "invoices", target_table: "customer_invoices",
      column_mappings: [ { "source_column" => "document_id", "target_column" => "doc_ref" } ]
    )

    post propose_destinations_connection_mappings_path(other_connection), params: { source_table: "invoices" }
    assert_response :not_found

    get edit_destinations_connection_mapping_path(other_connection, other_mapping)
    assert_response :not_found

    post confirm_destinations_connection_mapping_path(other_connection, other_mapping)
    assert_response :not_found
    assert_equal "proposed", other_mapping.reload.status
  end

  private

  def create_connection!(tenant:, label: "warehouse", snapshot: SNAPSHOT)
    Destination::DatabaseConnection.create!(
      tenant: tenant, label: label, adapter: "postgresql",
      host: "db.customer.example", port: 5432, database_name: "erp",
      username: "writer", password: "secret-value", ssl_mode: "prefer",
      schema_snapshot: snapshot, schema_captured_at: snapshot.present? ? Time.current : nil
    )
  end

  def propose!
    post propose_destinations_connection_mappings_path(@connection), params: { source_table: "invoices" }
    Destination::FieldMapping.last
  end
end
