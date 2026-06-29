# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class InvoiceTest < Minitest::Test
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_001_minimal_visual_usd.json")

    def test_loads_canonical_invoice_attributes_without_coercing_money_strings
      invoice = Canonical::Invoice.from_json(FIXTURE_PATH.read)

      assert_equal "2.0", invoice.schema_version
      assert_equal "fix_001_minimal_visual_usd", invoice.document_id
      assert_equal "invoice", invoice.document_type
      assert_equal "USD", invoice.currency
      assert_equal "100.00", invoice.payable_amount
      assert_instance_of String, invoice.payable_amount
    end

    def test_returns_defensive_hash_copies
      invoice = Canonical::Invoice.from_json(FIXTURE_PATH.read)
      copy = invoice.to_h
      copy["invoice"]["currency"] = "EUR"

      assert_equal "USD", invoice.currency
    end
  end
end
