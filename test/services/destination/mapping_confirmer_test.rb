# frozen_string_literal: true

require "test_helper"

module Destination
  class MappingConfirmerTest < ActiveSupport::TestCase
    SNAPSHOT = {
      "tables" => [
        {
          "name" => "customer_invoices",
          "columns" => [
            { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => true },
            { "name" => "grand_total", "data_type" => "numeric", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
          ]
        }
      ]
    }.freeze

    test "confirms a mapping that validates cleanly" do
      mapping = create_mapping!(column_mappings: [
        { "source_column" => "document_id", "target_column" => "doc_ref" },
        { "source_column" => "payable_amount", "target_column" => "grand_total" }
      ])

      result = MappingConfirmer.call(mapping: mapping)

      assert_predicate result, :confirmed?
      assert_equal "confirmed", mapping.reload.status
      assert_empty result.report.errors
    end

    test "marks a failing mapping invalid and reports why" do
      mapping = create_mapping!(column_mappings: [
        { "source_column" => "payable_amount", "target_column" => "grand_total" }
      ])

      result = MappingConfirmer.call(mapping: mapping)

      assert_not result.confirmed?
      assert_equal "invalid", mapping.reload.status
      assert_includes result.report.errors.map { |error| error["code"] }, "unmapped_required_source"
    end

    private

    def create_mapping!(column_mappings:)
      tenant = Tenant.create!(name: "Confirm Tenant", slug: "confirm-#{SecureRandom.hex(3)}", hosting_region: "local", storage_region: "local")
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "warehouse", adapter: "postgresql",
        host: "db.customer.example", port: 5432, database_name: "erp",
        username: "writer", password: "secret", ssl_mode: "prefer",
        schema_snapshot: SNAPSHOT, schema_captured_at: Time.current
      )
      Destination::FieldMapping.create!(
        tenant: tenant, database_connection: connection,
        source_table: "invoices", target_table: "customer_invoices",
        column_mappings: column_mappings
      )
    end
  end
end
