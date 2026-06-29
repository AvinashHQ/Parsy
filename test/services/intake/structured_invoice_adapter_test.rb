# frozen_string_literal: true

require "canonical_test_helper"

module Intake
  class StructuredInvoiceAdapterTest < Minitest::Test
    def test_maps_synthetic_ubl_invoice_to_canonical_v2
      result = adapter.call(xml: ubl_xml, filename: "ubl.xml")

      assert result.mapped?, result.errors.inspect
      invoice = result.canonical
      assert_instance_of Canonical::Invoice, invoice
      assert_equal "ubl", invoice.source.family
      assert_equal "structured_parser", invoice.source.route
      assert_equal "oasis_ubl_invoice", invoice.source.profile
      assert_equal "UBL-INV-100", invoice.details.number
      assert_equal "2026-06-20", invoice.details.issue_date
      assert_equal "EUR", invoice.currency
      assert_equal "1200.00", invoice.payable_amount
      assert_equal "Acme Structured GmbH", invoice.supplier.display_name
      assert_empty Canonical::SchemaValidator.new.validate(invoice.to_h)
    end

    def test_maps_synthetic_cii_invoice_to_canonical_v2
      result = adapter.call(xml: cii_xml, filename: "cii.xml")

      assert result.mapped?, result.errors.inspect
      invoice = result.canonical
      assert_equal "cii", invoice.source.family
      assert_equal "uncefact_cii", invoice.source.profile
      assert_equal "CII-INV-200", invoice.details.number
      assert_equal "2026-06-21", invoice.details.issue_date
      assert_equal "KWD", invoice.currency
      assert_equal "10.125", invoice.payable_amount
      assert_empty Canonical::SchemaValidator.new.validate(invoice.to_h)
    end

    def test_unknown_structured_xml_quarantines_without_visual_fallback_or_content_in_observability
      result = adapter.call(xml: "<PortalInvoice><Number>SECRET-999</Number></PortalInvoice>", filename: "portal.xml")

      assert result.quarantined?
      assert_includes result.errors, "UNSUPPORTED_STRUCTURED_FORMAT"
      assert_nil result.canonical
      assert_equal "quarantine", result.detection.route
      refute_includes result.observability.to_s, "SECRET-999"
    end

    def test_xml_entity_expansion_risk_quarantines
      result = adapter.call(xml: "<!DOCTYPE x [ <!ENTITY xxe SYSTEM 'file:///etc/passwd'> ]><Invoice>&xxe;</Invoice>", filename: "bad.xml")

      assert result.quarantined?
      assert_includes result.errors, "XML_ENTITY_EXPANSION_RISK"
      assert_nil result.canonical
    end

    private

    def adapter
      @adapter ||= StructuredInvoiceAdapter.new
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

    def cii_xml
      <<~XML
        <?xml version="1.0"?>
        <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
          <rsm:ExchangedDocument><ram:ID>CII-INV-200</ram:ID></rsm:ExchangedDocument>
          <ram:IssueDateTime><udt:DateTimeString format="102">20260621</udt:DateTimeString></ram:IssueDateTime>
          <ram:SupplyChainTradeTransaction>
            <ram:IncludedSupplyChainTradeLineItem>
              <ram:SpecifiedTradeProduct><ram:Name>Structured consulting</ram:Name></ram:SpecifiedTradeProduct>
              <ram:SpecifiedLineTradeSettlement><ram:LineTotalAmount>10.125</ram:LineTotalAmount></ram:SpecifiedLineTradeSettlement>
            </ram:IncludedSupplyChainTradeLineItem>
            <ram:ApplicableHeaderTradeAgreement><ram:SellerTradeParty><ram:Name>CII Supplier</ram:Name></ram:SellerTradeParty></ram:ApplicableHeaderTradeAgreement>
            <ram:ApplicableHeaderTradeSettlement>
              <ram:InvoiceCurrencyCode>KWD</ram:InvoiceCurrencyCode>
              <ram:TaxBasisTotalAmount>10.125</ram:TaxBasisTotalAmount>
              <ram:TaxTotalAmount>0</ram:TaxTotalAmount>
              <ram:GrandTotalAmount>10.125</ram:GrandTotalAmount>
              <ram:DuePayableAmount>10.125</ram:DuePayableAmount>
            </ram:ApplicableHeaderTradeSettlement>
          </ram:SupplyChainTradeTransaction>
        </rsm:CrossIndustryInvoice>
      XML
    end
  end
end
