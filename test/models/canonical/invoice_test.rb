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
    def test_exposes_nested_value_objects
      invoice = Canonical::Invoice.from_json(FIXTURE_PATH.read)

      assert_instance_of Canonical::Source, invoice.source
      assert_equal "visual_pdf", invoice.source.family
      assert_instance_of Canonical::Locale, invoice.locale
      assert_equal "global_generic_v1", invoice.locale.applied_region_pack_id
      assert_instance_of Canonical::Party, invoice.supplier
      assert_equal "Northstar Services Ltd", invoice.supplier.display_name
      assert_equal "BUSINESS_REGISTRATION", invoice.supplier.identifiers.first.scheme
      assert_equal "GB", invoice.supplier.address.country_code
      assert_instance_of Canonical::InvoiceDetails, invoice.details
      assert_equal "INV-2026-1042", invoice.details.number
      assert_instance_of Canonical::Totals, invoice.totals
      assert_equal "100.00", invoice.totals.payable_amount
      assert_instance_of Canonical::LineItem, invoice.line_items.first
      assert_equal "100.00", invoice.line_items.first.line_net_amount
      assert_instance_of Canonical::Evidence, invoice.evidence.first
      assert_equal "/invoice/number", invoice.evidence.first.field_path
    end

    def test_returns_defensive_hash_copies
      invoice = Canonical::Invoice.from_json(FIXTURE_PATH.read)
      copy = invoice.to_h
      copy["invoice"]["currency"] = "EUR"

      assert_equal "USD", invoice.currency
    end

    def test_canonical_attributes_are_deep_frozen
      invoice = Canonical::Invoice.from_json(FIXTURE_PATH.read)

      assert_raises(FrozenError) { invoice.attributes["invoice"]["currency"] = "EUR" }
      assert_equal "USD", invoice.currency
    end
  end
end
