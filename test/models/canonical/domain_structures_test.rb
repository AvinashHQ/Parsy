# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class DomainStructuresTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_credit_note_preserves_generic_original_invoice_reference
      invoice = Canonical::Invoice.from_json(FIXTURE_DIR.join("fix_002_credit_note_gbp.json").read)
      reference = invoice.references.first

      assert_equal "credit_note", invoice.document_type
      assert_instance_of Canonical::Reference, reference
      assert_equal "original_invoice", reference.type
      assert_equal "INV-2026-1042", reference.value_text
      assert_equal "2026-06-15", reference.issue_date
    end

    def test_parties_identifiers_and_addresses_are_typed_collections
      invoice = Canonical::Invoice.from_json(FIXTURE_DIR.join("fix_005_generic_vat_eur.json").read)

      assert_instance_of Canonical::Party, invoice.supplier
      assert_instance_of Canonical::Identifier, invoice.supplier.identifiers.first
      assert_equal "VAT", invoice.supplier.identifiers.first.scheme
      assert_equal "tax", invoice.supplier.identifiers.first.purpose
      assert_instance_of Canonical::Address, invoice.supplier.address
      assert_equal "GB", invoice.supplier.address.country_code
      assert_equal "GB", invoice.supplier.address.normalized_country_code
      assert_instance_of Canonical::Party, invoice.buyer
      assert_equal "FR", invoice.buyer.address.normalized_country_code
    end

    def test_generic_tax_breakdowns_do_not_require_region_specific_classes
      invoice = Canonical::Invoice.from_json(FIXTURE_DIR.join("fix_005_generic_vat_eur.json").read)
      breakdown = invoice.tax_breakdowns.first
      line_breakdown = invoice.line_items.first.tax_breakdowns.first

      assert_instance_of Canonical::TaxBreakdown, breakdown
      assert_equal "VAT", breakdown.tax_type
      assert_equal "GB", breakdown.jurisdiction_code
      assert_equal "S", breakdown.category_code
      assert_equal "20", breakdown.rate
      assert_equal "add", breakdown.payable_effect
      assert_instance_of Canonical::TaxBreakdown, line_breakdown
      assert_equal breakdown.to_h, line_breakdown.to_h
    end

    def test_line_items_expose_generic_classifications_allowances_and_taxes
      invoice = Canonical::Invoice.from_json(FIXTURE_DIR.join("fix_005_generic_vat_eur.json").read)
      line_item = invoice.line_items.first

      assert_instance_of Canonical::LineItem, line_item
      assert_empty line_item.classifications
      assert_empty line_item.allowances_charges
      assert_equal "1", line_item.quantity
      assert_equal "1000.00", line_item.unit_price
      assert_instance_of Canonical::TaxBreakdown, line_item.tax_breakdowns.first
    end

    def test_payment_means_are_typed_without_export_adapter_assumptions
      invoice = Canonical::Invoice.from_json(FIXTURE_DIR.join("fix_005_generic_vat_eur.json").read)

      assert_instance_of Canonical::Payment, invoice.payment
      assert_equal "Payment due in 30 days", invoice.payment.terms_text
      assert_instance_of Canonical::PaymentMean, invoice.payment.means.first
      assert_equal "30", invoice.payment.means.first.type_code
      assert_equal "1234", invoice.payment.means.first.iban_last4
    end

    def test_no_country_specific_core_model_classes_are_defined
      country_specific_constants = Canonical.constants.grep(/GST|GSTIN|EU|VAT|TALLY|INDIA|PEPPOL|UBL|CII/)

      assert_empty country_specific_constants
    end
  end
end
