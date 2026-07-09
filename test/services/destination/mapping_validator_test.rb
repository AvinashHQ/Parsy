# frozen_string_literal: true

require "test_helper"

module Destination
  class MappingValidatorTest < ActiveSupport::TestCase
    SNAPSHOT = {
      "tables" => [
        {
          "name" => "customer_invoices",
          "columns" => [
            { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => true },
            { "name" => "inv_no", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "grand_total", "data_type" => "numeric", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "issued_on", "data_type" => "date", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "created_by", "data_type" => "character varying", "nullable" => false, "default" => "'system'::character varying", "primary_key" => false, "unique" => false },
            { "name" => "custom_flags", "data_type" => "jsonb", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
          ]
        }
      ]
    }.freeze

    test "a clean mapping validates with no errors" do
      report = MappingValidator.call(mapping: build_mapping, snapshot: SNAPSHOT)

      assert_predicate report, :valid?
      assert_empty report.warnings
    end

    test "missing target table blocks and still reports required-source gaps" do
      mapping = build_mapping(target_table: "wrong_table", column_mappings: [
        { "source_column" => "invoice_number", "target_column" => "inv_no" }
      ])

      report = MappingValidator.call(mapping: mapping, snapshot: SNAPSHOT)

      codes = report.errors.map { |error| error["code"] }
      assert_includes codes, "schema_snapshot_missing_target_table"
      assert_includes codes, "unmapped_required_source"
    end

    test "flags unknown source columns, duplicate targets, and missing target columns" do
      mapping = build_mapping(column_mappings: [
        { "source_column" => "document_id", "target_column" => "doc_ref" },
        { "source_column" => "invoice_number", "target_column" => "not_there" },
        { "source_column" => "supplier_name", "target_column" => "inv_no" },
        { "source_column" => "buyer_name", "target_column" => "inv_no" }
      ])
      mapping.column_mappings << { "source_column" => "made_up", "target_column" => "grand_total" }

      report = MappingValidator.call(mapping: mapping, snapshot: SNAPSHOT)

      codes = report.errors.map { |error| error["code"] }
      assert_includes codes, "unknown_source_column"
      assert_includes codes, "missing_target_column"
      assert_includes codes, "duplicate_target_column"
    end

    test "flags type mismatches between source kinds and target column types" do
      mapping = build_mapping(column_mappings: [
        { "source_column" => "document_id", "target_column" => "doc_ref" },
        { "source_column" => "invoice_number", "target_column" => "inv_no" },
        { "source_column" => "issue_date", "target_column" => "grand_total" },
        { "source_column" => "payable_amount", "target_column" => "issued_on" },
        { "source_column" => "supplier_name", "target_column" => "custom_flags" }
      ])

      report = MappingValidator.call(mapping: mapping, snapshot: SNAPSHOT)

      mismatches = report.errors.select { |error| error["code"] == "type_mismatch" }
      assert_equal %w[issue_date payable_amount], mismatches.map { |error| error["source_column"] }.sort
      unknown_types = report.warnings.select { |warning| warning["code"] == "unknown_target_type" }
      assert_equal [ "custom_flags" ], unknown_types.map { |warning| warning["target_column"] }
    end

    test "requires document keys and NOT NULL no-default target columns to be mapped" do
      mapping = build_mapping(column_mappings: [
        { "source_column" => "payable_amount", "target_column" => "grand_total" }
      ])

      report = MappingValidator.call(mapping: mapping, snapshot: SNAPSHOT)

      codes = report.errors.map { |error| error["code"] }
      assert_includes codes, "unmapped_required_source"
      required_targets = report.errors.select { |error| error["code"] == "unmapped_required_target" }
      assert_equal %w[doc_ref inv_no], required_targets.map { |error| error["target_column"] }.sort,
                   "created_by has a default and must not be required"
    end

    test "warns when the document key target lacks a unique constraint" do
      mapping = build_mapping(column_mappings: [
        { "source_column" => "document_id", "target_column" => "inv_no" },
        { "source_column" => "invoice_number", "target_column" => "doc_ref" }
      ])

      report = MappingValidator.call(mapping: mapping, snapshot: SNAPSHOT)

      warning_codes = report.warnings.map { |warning| warning["code"] }
      assert_includes warning_codes, "document_key_not_unique"
    end

    test "line_items requires line_id as well" do
      mapping = build_mapping(source_table: "line_items", column_mappings: [
        { "source_column" => "document_id", "target_column" => "doc_ref" }
      ])

      report = MappingValidator.call(mapping: mapping, snapshot: SNAPSHOT)

      required = report.errors.select { |error| error["code"] == "unmapped_required_source" }
      assert_equal [ "line_id" ], required.map { |error| error["source_column"] }
    end

    private

    def build_mapping(source_table: "invoices", target_table: "customer_invoices", column_mappings: nil)
      tenant = Tenant.create!(name: "Val Tenant", slug: "val-#{SecureRandom.hex(3)}", hosting_region: "local", storage_region: "local")
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "warehouse", adapter: "postgresql",
        host: "db.customer.example", port: 5432, database_name: "erp",
        username: "writer", password: "secret", ssl_mode: "prefer"
      )
      Destination::FieldMapping.new(
        tenant: tenant,
        database_connection: connection,
        source_table: source_table,
        target_table: target_table,
        column_mappings: column_mappings || [
          { "source_column" => "document_id", "target_column" => "doc_ref" },
          { "source_column" => "invoice_number", "target_column" => "inv_no" },
          { "source_column" => "payable_amount", "target_column" => "grand_total" },
          { "source_column" => "issue_date", "target_column" => "issued_on" }
        ]
      )
    end
  end
end
