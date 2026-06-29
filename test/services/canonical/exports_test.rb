# frozen_string_literal: true

require "canonical_test_helper"
require "csv"
require "json"
require "zip"

module Canonical
  class ExportsTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_json_export_round_trips_without_mutating_canonical_invoice
      invoice = invoice("fix_005_generic_vat_eur.json")
      before = invoice.to_h

      payload = Canonical::Exports::CanonicalJson.call(invoice: invoice, review_status: "APPROVED")
      parsed = JSON.parse(payload)

      assert_equal "m1.0", parsed.fetch("export_version")
      assert_equal "2.0", parsed.fetch("schema_version")
      assert_equal "APPROVED", parsed.fetch("review_status")
      assert_equal before, Canonical::Invoice.from_hash(parsed.fetch("canonical_invoice")).to_h
      assert_equal before, invoice.to_h
    end

    def test_csv_bundle_reconciles_to_canonical_document
      invoice = invoice("fix_005_generic_vat_eur.json")
      bundle = Canonical::Exports::NormalizedCsv.call(invoices: [ invoice ], review_statuses: { invoice.document_id => "APPROVED" })

      invoice_rows = CSV.parse(bundle.fetch("Invoices.csv"), headers: true)
      party_rows = CSV.parse(bundle.fetch("Parties.csv"), headers: true)
      identifier_rows = CSV.parse(bundle.fetch("PartyIdentifiers.csv"), headers: true)
      tax_rows = CSV.parse(bundle.fetch("TaxBreakdowns.csv"), headers: true)
      line_rows = CSV.parse(bundle.fetch("LineItems.csv"), headers: true)

      assert_equal 1, invoice_rows.length
      assert_equal "2.0", invoice_rows.first.fetch("schema_version")
      assert_equal "APPROVED", invoice_rows.first.fetch("review_status")
      assert_equal invoice.payable_amount, invoice_rows.first.fetch("payable_amount")
      assert_equal invoice.currency, invoice_rows.first.fetch("currency")
      assert_equal 2, party_rows.length
      assert_equal 2, identifier_rows.length
      assert_equal 2, tax_rows.length
      assert_equal 1, line_rows.length
      assert_equal invoice.line_items.first.line_net_amount, line_rows.first.fetch("line_net_amount")
    end

    def test_csv_export_neutralizes_formula_injection_at_cell_boundaries
      invoice = invoice("fix_012_formula_injection_values.json")
      bundle = Canonical::Exports::NormalizedCsv.call(invoices: [ invoice ], review_statuses: { invoice.document_id => "APPROVED" })

      invoices = CSV.parse(bundle.fetch("Invoices.csv"), headers: true)
      parties = CSV.parse(bundle.fetch("Parties.csv"), headers: true)
      identifiers = CSV.parse(bundle.fetch("PartyIdentifiers.csv"), headers: true)
      lines = CSV.parse(bundle.fetch("LineItems.csv"), headers: true)
      taxes = CSV.parse(bundle.fetch("TaxBreakdowns.csv"), headers: true)

      assert_equal "'=INV-012", invoices.first.fetch("invoice_number")
      assert_equal "'=HYPERLINK(\"http://evil.test\")", parties.first.fetch("display_name")
      assert_equal "'@VAT-LOOKUP", identifiers.first.fetch("value")
      assert_equal "'=cmd|calc", lines.first.fetch("description")
      assert_equal "'=VAT 20%", taxes.first.fetch("source_label")
    end

    def test_workbook_export_contains_expected_sheets
      invoice = invoice("fix_005_generic_vat_eur.json")
      bytes = Canonical::Exports::Workbook.call(invoices: [ invoice ], review_statuses: { invoice.document_id => "APPROVED" })

      entries = []
      Zip::File.open_buffer(StringIO.new(bytes)) { |zip| entries = zip.map(&:name) }

      assert_includes entries, "xl/worksheets/sheet1.xml"
      assert_includes entries, "xl/worksheets/sheet5.xml"
      assert_operator bytes.bytesize, :>, 1_000
    end

    def test_export_service_refuses_unapproved_revisions
      invoice = invoice("fix_005_generic_vat_eur.json")
      revision = Canonical::Exports::RevisionSnapshot.new(revision_id: "rev-1", invoice: invoice, review_status: "NEEDS_REVIEW")

      assert_raises(Canonical::Exports::ExportService::UnapprovedRevision) do
        Canonical::Exports::ExportService.call(revisions: [ revision ], format: :csv)
      end
    end

    def test_export_service_delegates_approved_revisions
      invoice = invoice("fix_005_generic_vat_eur.json")
      revision = Canonical::Exports::RevisionSnapshot.new(revision_id: "rev-1", invoice: invoice, review_status: "APPROVED")

      bundle = Canonical::Exports::ExportService.call(revisions: [ revision ], format: :csv)

      assert_includes bundle.keys, "Invoices.csv"
    end

    private

    def invoice(filename)
      Canonical::Invoice.from_json(FIXTURE_DIR.join(filename).read)
    end
  end
end
