# frozen_string_literal: true

require "test_helper"

module Destination
  class RowTransformerTest < ActiveSupport::TestCase
    COLUMNS = {
      "doc_ref" => { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil },
      "grand_total" => { "name" => "grand_total", "data_type" => "numeric", "nullable" => true, "default" => nil },
      "issued_on" => { "name" => "issued_on", "data_type" => "date", "nullable" => true, "default" => nil },
      "due_text" => { "name" => "due_text", "data_type" => "text", "nullable" => true, "default" => nil },
      "must_have" => { "name" => "must_have", "data_type" => "character varying", "nullable" => false, "default" => nil },
      "seq" => { "name" => "seq", "data_type" => "integer", "nullable" => true, "default" => nil }
    }.freeze

    ROW = {
      "document_id" => "doc_1", "payable_amount" => "1200.50", "issue_date" => "2026-06-15",
      "due_date" => "2026-07-15", "supplier_name" => nil, "invoice_number" => "INV-9"
    }.freeze

    test "coerces typed targets and keeps text targets as canonical strings" do
      result = transform(ROW, [
        %w[document_id doc_ref], %w[payable_amount grand_total], %w[issue_date issued_on], %w[due_date due_text]
      ])

      assert_predicate result, :ok?
      assert_equal "doc_1", result.values["doc_ref"]
      assert_equal BigDecimal("1200.50"), result.values["grand_total"]
      assert_equal Date.new(2026, 6, 15), result.values["issued_on"]
      assert_equal "2026-07-15", result.values["due_text"], "date into a text column stays the canonical string"
    end

    test "nil values pass through to nullable targets and block NOT NULL targets" do
      nullable = transform(ROW, [ %w[document_id doc_ref], %w[supplier_name due_text] ])
      assert_predicate nullable, :ok?
      assert_nil nullable.values["due_text"]

      blocked = transform(ROW, [ %w[supplier_name must_have] ])
      assert_not blocked.ok?
      assert_equal "null_value_for_not_null_target", blocked.issues.sole["code"]
      assert_equal "supplier_name", blocked.issues.sole["source_column"]
    end

    test "unparseable values surface content-free issue codes, never values" do
      result = transform({ "payable_amount" => "12,00", "issue_date" => "15/06/2026" }, [
        %w[payable_amount grand_total], %w[issue_date issued_on]
      ])

      assert_not result.ok?
      codes = result.issues.map { |issue| issue["code"] }
      assert_includes codes, "unparseable_decimal"
      assert_includes codes, "unparseable_date"
      assert_no_match(/12,00|15\/06/, result.issues.to_json)
    end

    test "line integers coerce and text into typed targets is rejected defensively" do
      line = transform({ "document_id" => "doc_1", "line_no" => 2 }, [ %w[document_id doc_ref], %w[line_no seq] ], source_table: "line_items")
      assert_predicate line, :ok?
      assert_equal 2, line.values["seq"]

      mismatch = transform({ "invoice_number" => "INV-9" }, [ %w[invoice_number grand_total] ])
      assert_not mismatch.ok?
      assert_equal "type_mismatch", mismatch.issues.sole["code"]
    end

    private

    def transform(row, pairs, source_table: "invoices")
      tenant = Tenant.create!(name: "RT", slug: "rt-#{SecureRandom.hex(3)}")
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "rt", adapter: "postgresql", host: "h", port: 5432,
        database_name: "d", username: "u", password: "p", ssl_mode: "prefer"
      )
      mapping = Destination::FieldMapping.new(
        tenant: tenant, database_connection: connection, source_table: source_table,
        target_table: "t",
        column_mappings: pairs.map { |source, target| { "source_column" => source, "target_column" => target } }
      )
      RowTransformer.call(row: row, mapping: mapping, columns: COLUMNS)
    end
  end
end
