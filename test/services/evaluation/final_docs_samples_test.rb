# frozen_string_literal: true

require "canonical_test_helper"
require "csv"
require "digest"
require "json"
require "rexml/document"

module Evaluation
  class FinalDocsSamplesTest < Minitest::Test
    SAMPLE_ROOT = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples")
    SYNTHETIC_ROOT = SAMPLE_ROOT.join("synthetic_corpus")

    def test_root_canonical_samples_validate_and_round_trip_through_json_export
      validator = Canonical::SchemaValidator.new

      {
        "canonical_invoice.json" => "EUR",
        "canonical_invoice_jpy.json" => "JPY"
      }.each do |filename, currency|
        attributes = JSON.parse(SAMPLE_ROOT.join(filename).read)

        assert_empty validator.validate(attributes), "expected #{filename} to match Canonical Invoice v2"
        invoice = Canonical::Invoice.from_hash(attributes)
        assert_equal currency, invoice.currency

        exported = JSON.parse(Canonical::Exports::CanonicalJson.call(invoice: invoice, review_status: "APPROVED"))
        assert_equal invoice.to_h, exported.fetch("canonical_invoice")
        assert_equal "APPROVED", exported.fetch("review_status")
      end
    end

    def test_root_flat_csv_samples_reconcile_to_canonical_sample
      canonical = JSON.parse(SAMPLE_ROOT.join("canonical_invoice.json").read)
      invoice = csv_rows("Invoices.csv").fetch(0)
      supplier = find_party("supplier")
      buyer = find_party("buyer")
      identifiers = csv_rows("PartyIdentifiers.csv")
      taxes = csv_rows("TaxBreakdowns.csv")
      line = csv_rows("LineItems.csv").fetch(0)

      assert_equal canonical.fetch("document_id"), invoice.fetch("document_id")
      assert_equal canonical.fetch("document_type"), invoice.fetch("document_type")
      assert_equal canonical.dig("source", "family"), invoice.fetch("source_family")
      assert_equal canonical.dig("invoice", "currency"), invoice.fetch("currency")
      assert_equal canonical.dig("totals", "payable_amount"), invoice.fetch("payable_amount")
      assert_equal canonical.dig("locale", "applied_region_pack", "id"), invoice.fetch("region_pack")
      assert_equal "APPROVED", invoice.fetch("review_status")

      assert_equal canonical.dig("supplier", "display_name"), supplier.fetch("display_name")
      assert_equal canonical.dig("supplier", "address", "country_code"), supplier.fetch("country_code")
      assert_equal canonical.dig("buyer", "display_name"), buyer.fetch("display_name")
      assert_equal canonical.dig("buyer", "address", "country_code"), buyer.fetch("country_code")
      assert_equal [ "buyer", "supplier" ], identifiers.map { |row| row.fetch("role") }.sort

      assert_equal canonical.fetch("line_items").first.fetch("line_id"), line.fetch("line_id")
      assert_equal canonical.fetch("line_items").first.fetch("line_net_amount"), line.fetch("line_net_amount")
      assert_equal canonical.fetch("tax_breakdowns").first.fetch("tax_amount"), taxes.find { |row| row.fetch("line_id").blank? }.fetch("tax_amount")
      assert_equal canonical.fetch("line_items").first.fetch("tax_breakdowns").first.fetch("tax_amount"), taxes.find { |row| row.fetch("line_id") == line.fetch("line_id") }.fetch("tax_amount")
    end

    def test_synthetic_corpus_manifest_files_match_checksums_and_intake_routes
      rows = CSV.read(SYNTHETIC_ROOT.join("manifest.csv"), headers: true).map(&:to_h)
      inspector = Intake::UploadInspector.new

      assert_equal 29, rows.length
      assert_equal 25, rows.count { |row| row.fetch("ground_truth").present? }

      rows.each do |row|
        fixture_id = row.fetch("fixture_id")
        path = SYNTHETIC_ROOT.join(row.fetch("file"))

        assert path.file?, "missing source fixture #{fixture_id}: #{path}"
        assert_equal row.fetch("sha256"), Digest::SHA256.file(path).hexdigest, "checksum mismatch for #{fixture_id}"

        result = inspector.inspect(path: path)
        assert_equal row.fetch("sha256"), result.sha256, "inspector checksum mismatch for #{fixture_id}"
        assert_equal row.fetch("expected_route"), result.route, "unexpected intake route for #{fixture_id}"
        if fixture_id == "HYB-001"
          assert_equal "hybrid_pdf_xml", result.detection.family
          assert_equal "pdf_embedded_invoice_xml", result.detection.profile
          assert_equal [ "oasis_ubl_invoice" ], result.detection.embedded_payloads.map(&:profile)
        end


        if row.fetch("expected_status") == "quarantined"
          assert result.quarantined? || result.rejected?, "expected #{fixture_id} to fail closed"
        else
          assert result.accepted?, "expected #{fixture_id} to be accepted"
        end
      end
    end

    def test_synthetic_ground_truth_and_expected_findings_are_parseable_and_schema_valid
      validator = Canonical::SchemaValidator.new
      rows = CSV.read(SYNTHETIC_ROOT.join("manifest.csv"), headers: true).map(&:to_h)

      rows.each do |row|
        fixture_id = row.fetch("fixture_id")
        if row.fetch("ground_truth").present?
          ground_truth = JSON.parse(SYNTHETIC_ROOT.join(row.fetch("ground_truth")).read)
          assert_empty validator.validate(ground_truth), "expected ground truth #{fixture_id} to match Canonical Invoice v2"
        end

        findings = JSON.parse(SYNTHETIC_ROOT.join(row.fetch("expected_findings")).read)
        assert_kind_of Array, findings, "expected findings #{fixture_id} must be an array"
      end
    end

    def test_structured_and_optional_adapter_samples_are_parseable
      xml = SAMPLE_ROOT.join("synthetic_corpus/documents/structured/XML-001_synthetic_ubl_invoice.xml").read
      structured_result = Intake::StructuredInvoiceAdapter.new.call(xml: xml, filename: "XML-001_synthetic_ubl_invoice.xml")

      assert structured_result.mapped?, structured_result.errors.inspect
      assert_empty Canonical::SchemaValidator.new.validate(structured_result.canonical.to_h)
      assert_equal "RD-2026-771", structured_result.canonical.details.number

      unknown_xml = SAMPLE_ROOT.join("synthetic_corpus/documents/structured/XML-002_unknown_profile.xml").read
      unknown_result = Intake::StructuredInvoiceAdapter.new.call(xml: unknown_xml, filename: "XML-002_unknown_profile.xml")
      assert unknown_result.quarantined?
      assert_equal "UNSUPPORTED_STRUCTURED_FORMAT", unknown_result.errors.fetch(0)

      tally_json = JSON.parse(SAMPLE_ROOT.join("adapters/india_tally/tally_purchase_voucher_draft.json").read)
      tally_xml = REXML::Document.new(SAMPLE_ROOT.join("adapters/india_tally/tally_purchase_voucher_draft.xml").read)
      entries = tally_json.fetch("voucher").fetch("entries")

      assert_equal "Purchase", tally_json.dig("voucher", "voucher_type")
      assert_equal 4, entries.length
      assert_equal 1_180.0, entries.select { |entry| entry.fetch("debit") }.sum { |entry| entry.fetch("amount") }
      assert_equal 1_180.0, entries.reject { |entry| entry.fetch("debit") }.sum { |entry| entry.fetch("amount") }
      assert_equal "Import Data", REXML::XPath.first(tally_xml, "//TALLYREQUEST").text
    end

    private

    def csv_rows(filename)
      CSV.read(SAMPLE_ROOT.join(filename), headers: true).map(&:to_h)
    end

    def find_party(role)
      csv_rows("Parties.csv").find { |row| row.fetch("role") == role }
    end
  end
end
