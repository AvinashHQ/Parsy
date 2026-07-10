# frozen_string_literal: true

require "test_helper"
require "json"

module Canonical
  module Exports
    class NormalizedRowsTest < ActiveSupport::TestCase
      FIXTURE = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

      def invoice
        @invoice ||= Canonical::Invoice.from_hash(JSON.parse(File.read(FIXTURE)))
      end

      test "decomposes an invoice into the five relational tables" do
        rows = NormalizedRows.call(invoices: [ invoice ], review_statuses: { invoice.document_id => "approved" })

        assert_equal NormalizedRows::TABLES.sort, rows.keys.sort

        header = rows.fetch("invoices").sole
        assert_equal "doc_demo_global_0001", header["document_id"]
        assert_equal "INV-2026-1042", header["invoice_number"]
        assert_equal "1200.00", header["payable_amount"]
        assert_equal "approved", header["review_status"]

        line = rows.fetch("line_items").sole
        assert_equal "line_1", line["line_id"]
        assert_equal 1, line["line_no"]
        assert_equal "1000.00", line["line_net_amount"]
      end

      test "row keys stay in lockstep with the CSV export headers" do
        rows = NormalizedRows.call(invoices: [ invoice ], review_statuses: { invoice.document_id => "approved" })

        assert_equal NormalizedCsv::INVOICE_HEADERS, rows.fetch("invoices").sole.keys
        assert_equal NormalizedCsv::LINE_HEADERS, rows.fetch("line_items").sole.keys
        assert_equal NormalizedCsv::PARTY_HEADERS, rows.fetch("parties").first.keys
        assert_equal NormalizedCsv::IDENTIFIER_HEADERS, rows.fetch("party_identifiers").first.keys
        assert_equal NormalizedCsv::TAX_HEADERS, rows.fetch("tax_breakdowns").first.keys
      end
    end
  end
end
