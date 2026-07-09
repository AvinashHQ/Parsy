# frozen_string_literal: true

require "test_helper"

module Destination
  class SourceSchemaTest < ActiveSupport::TestCase
    test "invoices columns stay in lockstep with the NormalizedCsv export headers" do
      expected = Canonical::Exports::NormalizedCsv::INVOICE_HEADERS

      assert_equal expected, SourceSchema.column_names("invoices")
    end

    test "line_items columns stay in lockstep with the NormalizedCsv export headers" do
      expected = Canonical::Exports::NormalizedCsv::LINE_HEADERS

      assert_equal expected, SourceSchema.column_names("line_items")
    end

    test "required columns exist in their tables" do
      SourceSchema.tables.each do |table|
        SourceSchema.required_columns(table).each do |column|
          assert SourceSchema.column?(table, column), "#{table} required column #{column} missing"
        end
      end
    end

    test "every column carries a coercion kind" do
      SourceSchema.tables.each do |table|
        SourceSchema.column_names(table).each do |column|
          assert_includes %i[text decimal date integer], SourceSchema.kind(table, column)
        end
      end
    end

    test "table lookup" do
      assert SourceSchema.table?("invoices")
      assert SourceSchema.table?("line_items")
      assert_not SourceSchema.table?("parties")
    end
  end
end
