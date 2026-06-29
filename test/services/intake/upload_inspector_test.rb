# frozen_string_literal: true

require "test_helper"
require "tempfile"

module Intake
  class UploadInspectorTest < ActiveSupport::TestCase
    PDF_BYTES = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF".b

    test "computes sha256 before routing and trusts magic bytes over extension" do
      result = inspector.inspect_bytes(PDF_BYTES, filename: "invoice.jpg", content_type: "image/jpeg")

      assert result.accepted?
      assert_equal Digest::SHA256.hexdigest(PDF_BYTES), result.sha256
      assert_equal "application/pdf", result.sniffed_mime_type
      assert_equal "visual_pdf", result.detection.family
      assert_equal "visual_model", result.route
      assert result.observability.fetch(:content_type_mismatch)
    end

    test "oversized file rejects with content-free metadata and hash" do
      bytes = "%PDF-1.7\n".b + ("0".b * 33)
      result = UploadInspector.new(max_bytes: 32).inspect_bytes(bytes, filename: "too-large.pdf", content_type: "application/pdf")

      assert result.rejected?
      assert_equal Digest::SHA256.hexdigest(bytes), result.sha256
      assert_equal "FILE_TOO_LARGE", result.rejection_code
      refute_includes result.observability.to_s, bytes
    end

    test "encrypted pdf rejects before model route" do
      result = inspector.inspect_bytes("%PDF-1.7\n<< /Encrypt 4 0 R >>\n%%EOF".b, filename: "locked.pdf", content_type: "application/pdf")

      assert result.quarantined?
      assert_equal "ENCRYPTED_PDF", result.rejection_code
      assert_equal "quarantine", result.route
    end

    test "unknown structured xml is quarantined and never sent to visual model" do
      result = inspector.inspect_bytes("<UnknownInvoice><Number>SECRET-123</Number></UnknownInvoice>", filename: "invoice.xml", content_type: "application/xml")

      assert result.quarantined?
      assert_equal "unknown_structured", result.detection.family
      assert_equal "UNSUPPORTED_STRUCTURED_FORMAT", result.rejection_code
      assert_equal "quarantine", result.route
      refute_includes result.observability.to_s, "SECRET-123"
    end

    test "known ubl and cii xml route to structured parser" do
      ubl = inspector.inspect_bytes(ubl_xml, filename: "ubl.xml", content_type: "application/xml")
      cii = inspector.inspect_bytes(cii_xml, filename: "cii.xml", content_type: "application/xml")

      assert_equal "ubl", ubl.detection.family
      assert_equal "oasis_ubl_invoice", ubl.detection.profile
      assert_equal "structured_parser", ubl.route
      assert_equal "cii", cii.detection.family
      assert_equal "uncefact_cii", cii.detection.profile
      assert_equal "structured_parser", cii.route
    end

    test "factur x pdf embedded payload routes hybrid compare with payload metadata only" do
      bytes = "%PDF-1.7\n/EmbeddedFiles /F (factur-x.xml) <?xml version='1.0'?><rsm:CrossIndustryInvoice xmlns:rsm='urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0'></rsm:CrossIndustryInvoice>\n%%EOF".b
      result = inspector.inspect_bytes(bytes, filename: "hybrid.pdf", content_type: "application/pdf")

      assert result.accepted?
      assert_equal "hybrid_pdf_xml", result.detection.family
      assert_equal "factur_x_zugferd", result.detection.profile
      assert_equal "hybrid_compare", result.route
      assert_equal 1, result.detection.embedded_payloads.length
      assert_equal 1, result.observability.fetch(:embedded_payload_count)
      refute_includes result.observability.to_s, "CrossIndustryInvoice"
    end

    test "standalone json is unsupported structured quarantine" do
      result = inspector.inspect_bytes('{"invoice":"SECRET-456"}', filename: "portal.json", content_type: "application/json")

      assert result.quarantined?
      assert_equal "UNSUPPORTED_STRUCTURED_FORMAT", result.rejection_code
      assert_equal "unknown_structured", result.detection.family
      refute_includes result.observability.to_s, "SECRET-456"
    end

    private

    def inspector
      @inspector ||= UploadInspector.new
    end

    def ubl_xml
      <<~XML
        <?xml version="1.0"?>
        <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">
          <ID>INV-UBL-1</ID>
        </Invoice>
      XML
    end

    def cii_xml
      <<~XML
        <?xml version="1.0"?>
        <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100">
          <rsm:ExchangedDocument><ram:ID>INV-CII-1</ram:ID></rsm:ExchangedDocument>
        </rsm:CrossIndustryInvoice>
      XML
    end
  end
end
