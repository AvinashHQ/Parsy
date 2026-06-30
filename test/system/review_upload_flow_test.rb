# frozen_string_literal: true

require "application_system_test_case"
require "tempfile"
require "zip"

class ReviewUploadFlowTest < ApplicationSystemTestCase
  PDF_BYTES = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF".b

  setup do
    @tenant = Tenant.create!(name: "System Upload Tenant", slug: "system-upload-#{SecureRandom.hex(4)}")
    @user = User.create!(tenant: @tenant, email: "system-upload@example.test", name: "System Upload", operator_token: "system-upload-token")
    visit new_session_path
    fill_in "Email", with: @user.email
    fill_in "Operator token", with: "system-upload-token"
    click_on "Sign in"
  end

  teardown do
    @zip_file&.close!
  rescue StandardError
    nil
  end

  test "operator uploads zip and opens no candidate PDF source" do
    @zip_file = zip_fixture([
      [ "structured.xml", ubl_xml ],
      [ "nested/visual.pdf", PDF_BYTES ]
    ])

    visit review_batches_path
    click_on "Upload invoices"
    attach_file "Invoice or ZIP file", @zip_file.path
    fill_in "Batch name", with: "System ZIP Upload"
    click_on "Upload invoices"

    assert_selector "section[aria-label='Batch progress']"
    assert_selector "section[aria-label='Intake results']"
    assert_text "System ZIP Upload"
    assert_text "Uploaded"

    batch = Review::Batch.find_by!(tenant: @tenant, name: "System ZIP Upload")
    xml_document = batch.documents.where(route: "structured_parser").sole
    pdf_document = batch.documents.where(route: "visual_model").sole

    assert_selector "a", text: xml_document.source_sha256.first(12)
    assert_selector "a", text: pdf_document.source_sha256.first(12)

    click_on pdf_document.source_sha256.first(12)
    assert_text "No candidate revision available"
    assert_link "Download source"
  end

  private

  def zip_fixture(entries)
    tempfile = Tempfile.new([ "system-upload", ".zip" ], binmode: true)
    Zip::OutputStream.open(tempfile.path) do |zip|
      entries.each do |name, bytes|
        zip.put_next_entry(name)
        zip.write(bytes)
      end
    end
    tempfile
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
