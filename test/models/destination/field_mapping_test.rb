# frozen_string_literal: true

require "test_helper"

module Destination
  class FieldMappingTest < ActiveSupport::TestCase
    test "valid with a known source table and well-formed mappings" do
      mapping = build_mapping

      assert_predicate mapping, :valid?
    end

    test "rejects unknown source tables and bad statuses" do
      assert_not build_mapping(source_table: "parties").valid?
      assert_not build_mapping(status: "pushed").valid?
      assert_not build_mapping(origin: "guessing").valid?
    end

    test "source table is unique per connection" do
      mapping = build_mapping
      mapping.save!

      duplicate = build_mapping(connection: mapping.database_connection, tenant: mapping.tenant)

      assert_not duplicate.valid?
    end

    test "tenant must match the connection tenant" do
      mapping = build_mapping
      other_tenant = create_tenant!(slug: "map-other")
      mapping.tenant = other_tenant

      assert_not mapping.valid?
      assert_includes mapping.errors[:tenant], "must match the destination connection tenant"
    end

    test "rejects malformed column mappings" do
      assert_not build_mapping(column_mappings: [ { "source_column" => "invoice_number" } ]).valid?
      assert_not build_mapping(column_mappings: [ { "source_column" => "not_a_column", "target_column" => "x" } ]).valid?
      assert_not build_mapping(column_mappings: [
        { "source_column" => "invoice_number", "target_column" => "a" },
        { "source_column" => "invoice_number", "target_column" => "b" }
      ]).valid?
    end

    test "normalizes symbol-keyed mapping entries" do
      mapping = build_mapping(column_mappings: [ { source_column: "invoice_number", target_column: "inv_no" } ])

      assert_predicate mapping, :valid?
      assert_equal "inv_no", mapping.target_column_for("invoice_number")
      assert_equal [ "invoice_number" ], mapping.mapped_source_columns
    end

    test "editing a confirmed mapping resets it to proposed" do
      mapping = build_mapping
      mapping.save!
      mapping.update!(status: "confirmed")

      mapping.update!(column_mappings: [ { "source_column" => "document_id", "target_column" => "doc_ref" } ])

      assert_equal "proposed", mapping.reload.status
    end

    test "explicit status transitions are not overridden" do
      mapping = build_mapping
      mapping.save!

      mapping.update!(status: "confirmed")

      assert_equal "confirmed", mapping.reload.status
    end

    test "destroying a connection removes its mappings" do
      mapping = build_mapping
      mapping.save!

      assert_difference -> { Destination::FieldMapping.count }, -1 do
        mapping.database_connection.destroy!
      end
    end

    private

    def create_tenant!(slug: "map-tenant")
      Tenant.create!(name: slug.titleize, slug: slug, hosting_region: "local", storage_region: "local")
    end

    def create_connection!(tenant:)
      Destination::DatabaseConnection.create!(
        tenant: tenant, label: "warehouse-#{SecureRandom.hex(2)}", adapter: "postgresql",
        host: "db.customer.example", port: 5432, database_name: "erp",
        username: "writer", password: "secret", ssl_mode: "prefer"
      )
    end

    def build_mapping(source_table: "invoices", status: "proposed", origin: "heuristic",
                      column_mappings: nil, connection: nil, tenant: nil)
      tenant ||= connection&.tenant || create_tenant!(slug: "map-#{SecureRandom.hex(3)}")
      connection ||= create_connection!(tenant: tenant)
      Destination::FieldMapping.new(
        tenant: tenant,
        database_connection: connection,
        source_table: source_table,
        target_table: "customer_invoices",
        column_mappings: column_mappings || [
          { "source_column" => "document_id", "target_column" => "doc_ref" },
          { "source_column" => "invoice_number", "target_column" => "inv_no" }
        ],
        status: status,
        origin: origin
      )
    end
  end
end
