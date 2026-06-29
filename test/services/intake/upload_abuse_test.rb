# frozen_string_literal: true

require "test_helper"

module Intake
  class UploadAbuseTest < ActiveSupport::TestCase
    test "malicious filenames are rejected before storage" do
      result = Intake::UploadInspector.new.inspect_bytes("%PDF-1.7\n%%EOF".b, filename: "../invoice.pdf", content_type: "application/pdf")

      assert_equal "rejected", result.status
      assert_equal "MALICIOUS_FILENAME", result.rejection_code
    end

    test "pdf page bombs are quarantined" do
      pages = Array.new(51, "/Type /Page").join("\n")
      result = Intake::UploadInspector.new.inspect_bytes("%PDF-1.7\n#{pages}\n%%EOF".b, filename: "large.pdf", content_type: "application/pdf")

      assert_equal "quarantined", result.status
      assert_equal "PDF_PAGE_LIMIT_EXCEEDED", result.rejection_code
    end

    test "xml network entity and oversize payloads are quarantined" do
      network = "<!DOCTYPE x SYSTEM 'https://attacker.invalid/e'>\n<Invoice/>"
      network_result = Intake::UploadInspector.new.inspect_bytes(network, filename: "invoice.xml", content_type: "application/xml")
      assert_equal "XML_ENTITY_EXPANSION_RISK", network_result.rejection_code

      oversized = "<Invoice>#{'x' * (Intake::UploadInspector::MAX_XML_BYTES + 1)}</Invoice>"
      oversized_result = Intake::UploadInspector.new.inspect_bytes(oversized, filename: "large.xml", content_type: "application/xml")
      assert_equal "XML_TOO_LARGE", oversized_result.rejection_code
    end
  end
end
