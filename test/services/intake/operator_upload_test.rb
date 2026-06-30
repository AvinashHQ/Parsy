# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "zip"

module Intake
  class OperatorUploadTest < ActiveSupport::TestCase
    PDF_BYTES = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF".b
    UploadedFile = Struct.new(:original_filename, :content_type, :tempfile, keyword_init: true)

    setup do
      @tenant = Tenant.create!(name: "Upload Tenant", slug: "upload-tenant-#{SecureRandom.hex(4)}")
      @actor = "operator@example.test"
      @tempfiles = []
    end

    teardown do
      @tempfiles.each do |tempfile|
        tempfile.close!
      rescue StandardError
        nil
      end
    end

    test "single ubl xml upload creates reviewable document with attached source" do
      result = OperatorUpload.call(tenant: @tenant, actor: @actor, upload: uploaded_file("invoice.xml", "application/xml", ubl_xml), batch_name: "XML Upload")

      assert_equal @tenant, result.batch.tenant
      assert_equal 1, result.batch.documents.count
      document = result.batch.documents.first
      assert document.source_file.attached?
      assert document.current_revision.present?
      assert_includes %w[needs_review ready_for_approval], document.status
      assert_includes result.flash_message, "1 document"
    end

    test "single visual pdf upload is queued without provider extraction" do
      result = forbid_provider_calls do
        OperatorUpload.call(tenant: @tenant, actor: @actor, upload: uploaded_file("invoice.pdf", "application/pdf", PDF_BYTES), batch_name: "PDF Upload")
      end

      document = result.batch.documents.sole
      assert_equal "needs_review", document.status
      assert_equal "visual_model", document.route
      assert document.source_file.attached?
      assert_nil document.current_revision
    end

    test "malicious single filename rejects before storage" do
      assert_no_difference -> { ActiveStorage::Blob.count } do
        assert_no_difference -> { ActiveStorage::Attachment.count } do
          result = OperatorUpload.call(tenant: @tenant, actor: @actor, upload: uploaded_file("../invoice.pdf", "application/pdf", PDF_BYTES), batch_name: "Malicious Upload")

          assert_nil result.batch
          assert_equal 1, result.entries.count(&:rejected?)
        end
      end
    end

    test "zip upload fans out safe entries and reports rejected entries" do
      result = OperatorUpload.call(tenant: @tenant, actor: @actor, upload: uploaded_file("invoices.zip", "application/zip", zip_bytes([
        [ "invoice.xml", ubl_xml ],
        [ "nested/invoice.pdf", PDF_BYTES ],
        [ "../evil.pdf", PDF_BYTES ]
      ])), batch_name: "ZIP Upload")

      assert_equal @tenant, result.batch.tenant
      assert_equal 2, result.batch.documents.count
      assert_equal 1, result.entries.count(&:rejected?)
      assert_equal 1, result.batch.documents.joins(:current_revision).count
      pdf_document = result.batch.documents.find_by!(route: "visual_model")
      assert_equal "needs_review", pdf_document.status
      assert_nil pdf_document.current_revision
      refute_includes result.flash_message, "evil"
      refute_includes result.flash_message, "UBL-INV-100"
    end

    test "zip bomb guards reject archive before storage" do
      entries = (OperatorUpload::MAX_ZIP_ENTRIES + 1).times.map { |index| [ "invoice-#{index}.pdf", PDF_BYTES ] }

      assert_no_difference -> { ActiveStorage::Blob.count } do
        assert_no_difference -> { ActiveStorage::Attachment.count } do
          result = OperatorUpload.call(tenant: @tenant, actor: @actor, upload: uploaded_file("bomb.zip", "application/zip", zip_bytes(entries)), batch_name: "Bomb Upload")

          assert_nil result.batch
          assert_predicate result.archive_error, :present?
        end
      end
    end

    test "duplicate source bytes in one zip persist once" do
      result = OperatorUpload.call(tenant: @tenant, actor: @actor, upload: uploaded_file("dupes.zip", "application/zip", zip_bytes([
        [ "first.pdf", PDF_BYTES ],
        [ "second.pdf", PDF_BYTES ]
      ])), batch_name: "Duplicate Upload")

      assert_equal 1, result.batch.documents.count
      assert_equal 1, result.entries.count(&:duplicate?)
      duplicate = result.entries.find(&:duplicate?)
      assert_equal "DUPLICATE_SOURCE", duplicate.rejection_code
      assert_includes result.flash_message, "1 document"
      assert_includes result.flash_message, "1 duplicate"
    end

    private

    def uploaded_file(filename, content_type, bytes)
      tempfile = Tempfile.new([ "operator-upload", File.extname(filename) ], binmode: true)
      tempfile.write(bytes)
      tempfile.rewind
      @tempfiles << tempfile
      UploadedFile.new(original_filename: filename, content_type: content_type, tempfile: tempfile)
    end

    def zip_bytes(entries)
      io = StringIO.new("".b)
      Zip::OutputStream.write_buffer(io) do |zip|
        entries.each do |name, bytes|
          zip.put_next_entry(name)
          zip.write(bytes)
        end
      end
      io.string.b
    end

    def forbid_provider_calls
      original = Extraction::ProviderAdapter.instance_method(:extract)
      Extraction::ProviderAdapter.define_method(:extract) do |*|
        raise "upload must not call extraction providers"
      end
      yield
    ensure
      Extraction::ProviderAdapter.define_method(:extract, original)
    end

    def ubl_xml
      <<~XML
        <?xml version="1.0"?>
        <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">
          <ID>UBL-INV-100</ID>
          <IssueDate>2026-06-20</IssueDate>
          <DocumentCurrencyCode>EUR</DocumentCurrencyCode>
          <AccountingSupplierParty><Party><PartyName><Name>Acme Structured GmbH</Name></PartyName></Party></AccountingSupplierParty>
          <TaxTotal><TaxAmount currencyID="EUR">200.00</TaxAmount></TaxTotal>
          <LegalMonetaryTotal>
            <LineExtensionAmount currencyID="EUR">1000.00</LineExtensionAmount>
            <TaxExclusiveAmount currencyID="EUR">1000.00</TaxExclusiveAmount>
            <TaxInclusiveAmount currencyID="EUR">1200.00</TaxInclusiveAmount>
            <PayableAmount currencyID="EUR">1200.00</PayableAmount>
          </LegalMonetaryTotal>
          <InvoiceLine>
            <ID>1</ID>
            <InvoicedQuantity unitCode="EA">1</InvoicedQuantity>
            <LineExtensionAmount currencyID="EUR">1000.00</LineExtensionAmount>
            <Item><Name>Structured services</Name></Item>
            <Price><PriceAmount currencyID="EUR">1000.00</PriceAmount></Price>
          </InvoiceLine>
        </Invoice>
      XML
    end
  end
end
