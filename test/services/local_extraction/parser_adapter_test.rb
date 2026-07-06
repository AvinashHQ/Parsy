# frozen_string_literal: true

require "test_helper"
require "base64"

module LocalExtraction
  class ParserAdapterTest < ActiveSupport::TestCase
    PNG_BYTES = "\x89PNG\r\n\x1A\nfixture".b
    TIFF_BYTES = "II*\x00fixture".b

    OcrClient = Struct.new(:response, :version, :calls, keyword_init: true) do
      def call(bytes:, metadata:, options:)
        calls << { byte_size: bytes.bytesize, metadata: metadata, options: options }
        response
      end
    end

    test "digital pdf parser returns normalized page layout table and evidence" do
      result = digital_parser.parse(bytes: digital_pdf("Supplier Secret INV-123 | 42.00"), metadata: {})

      assert result.accepted?
      assert_equal "digital_pdf", result.document.source_type
      assert_equal 1, result.document.pages.length
      page = result.document.pages.first
      assert_equal 612, page.width
      assert_equal 792, page.height
      assert_equal "Supplier Secret INV-123 | 42.00", page.layout.first.text
      assert_equal [ [ "Supplier Secret INV-123", "42.00" ] ], page.tables.first.rows
      assert_equal "digital_pdf", page.evidence.first.source
      assert_equal DigitalPdfParser::VERSION, result.metadata.fetch(:parser_version)
      assert_equal 12_345, result.metadata.fetch(:peak_memory_kb)
      assert_equal 7.0, result.metadata.fetch(:runtime_ms)
      assert_equal "deterministic_pdf_text_boundary", result.metadata.fetch(:options).fetch(:parser)
      refute_includes result.observability.to_s, "Supplier Secret"
      refute_includes result.observability.to_s, "INV-123"
    end

    test "digital pdf parser returns safe corrupt failure with content free metadata" do
      bytes = "%PDF-1.7\nBT (Leaked Party INV-999) Tj ET".b
      result = digital_parser.parse(bytes: bytes, metadata: {})

      assert result.failed?
      assert_equal "PDF_CORRUPT", result.error_code
      assert_nil result.document
      assert_equal DigitalPdfParser::VERSION, result.metadata.fetch(:parser_version)
      assert_equal 12_345, result.metadata.fetch(:peak_memory_kb)
      refute_includes result.observability.to_s, "Leaked Party"
      refute_includes result.observability.to_s, "INV-999"
    end

    test "digital pdf parser classifies scanned pdf as safe OCR handoff failure" do
      bytes = "%PDF-1.7\n1 0 obj << /Type /Page /Resources << /XObject << /Im0 2 0 R >> >> >>\nendobj\n%%EOF".b
      result = digital_parser.parse(bytes: bytes, metadata: {})

      assert result.failed?
      assert_equal "SCANNED_PDF_REQUIRES_OCR", result.error_code
      assert_equal DigitalPdfParser::VERSION, result.metadata.fetch(:parser_version)
    end

    test "ocr adapter normalizes image output and quality warnings without source observability" do
      client = OcrClient.new(
        version: "fixture-ocr-2.0",
        calls: [],
        response: {
          pages: [
            {
              number: 1,
              width: 1000,
              height: 1400,
              rotation: 90,
              skew_degrees: 3.1,
              blur_score: 0.2,
              text: "Hidden Supplier INV-777",
              confidence: 0.81,
              tables: [ { rows: [ [ "Description", "Total" ], [ "Service", "99.00" ] ] } ]
            }
          ],
          metadata: { version: "fixture-ocr-2.1", options: { language: "eng" }, peak_memory_kb: 45_678 }
        }
      )

      result = ocr_adapter(client).extract(bytes: PNG_BYTES, metadata: { blur_score: 0.1 })

      assert result.accepted?
      assert_equal "ocr", result.document.source_type
      page = result.document.pages.first
      assert_equal "Hidden Supplier INV-777", page.layout.first.text
      assert_equal 0.81, page.layout.first.confidence
      assert_equal [ [ "Description", "Total" ], [ "Service", "99.00" ] ], page.tables.first.rows
      assert_equal [ "BLURRED_IMAGE", "ROTATED_PAGE", "SKEWED_PAGE" ], result.warnings
      assert_equal [ "BLURRED_IMAGE", "ROTATED_PAGE", "SKEWED_PAGE" ], page.quality_warnings
      assert_equal "image/png", result.metadata.fetch(:input_mime_type)
      assert_equal OcrEvidenceAdapter::VERSION, result.metadata.fetch(:adapter_version)
      assert_equal "fixture-ocr-2.1", result.metadata.fetch(:ocr_version)
      assert_equal 12_345, result.metadata.fetch(:peak_memory_kb)
      assert_equal 7.0, result.metadata.fetch(:runtime_ms)
      assert_equal({ language: "eng" }, result.metadata.fetch(:ocr_options))
      refute_includes result.observability.to_s, "Hidden Supplier"
      refute_includes result.observability.to_s, "INV-777"
      assert_equal 1, client.calls.length
    end

    test "ocr adapter returns deterministic TIFF safe failure before client call" do
      client = OcrClient.new(response: { pages: [ { text: "Should not run" } ] }, version: "fixture-ocr", calls: [])

      result = ocr_adapter(client).extract(bytes: TIFF_BYTES, metadata: { skew_degrees: 4.0 })

      assert result.failed?
      assert_equal "TIFF_REQUIRES_TRANSCODE", result.error_code
      assert_equal [ "SKEWED_PAGE", "TIFF_INPUT" ], result.warnings
      assert_equal "image/tiff", result.metadata.fetch(:input_mime_type)
      assert_equal OcrEvidenceAdapter::VERSION, result.metadata.fetch(:adapter_version)
      assert_equal 12_345, result.metadata.fetch(:peak_memory_kb)
      assert_empty client.calls
      refute_includes result.observability.to_s, "Should not run"
    end

    test "pdf rasterizer writes binary PDF bytes to python without transcoding" do
      binary_pdf = "%PDF-1.7\n".b + [ 0x93, 0x94, 0xFF ].pack("C*")
      capture = lambda do |*command, stdin_data:, binmode: false|
        assert_equal [ "python3", "-c", PdfRasterizer::RENDER_SCRIPT ], command
        assert binmode, "PDF stdin/stdout must use binary mode or Ruby transcodes ASCII-8BIT bytes to UTF-8"
        assert_equal binary_pdf, stdin_data
        [ Base64.strict_encode64(PNG_BYTES), "", Struct.new(:success?).new(true) ]
      end

      png = PdfRasterizer.new(capture3: capture).call(bytes: binary_pdf)

      assert_equal PNG_BYTES, png
    end


    private

    def digital_parser
      DigitalPdfParser.new(clock: deterministic_clock, memory_probe: -> { 12_345 })
    end

    def ocr_adapter(client)
      OcrEvidenceAdapter.new(client: client, clock: deterministic_clock, memory_probe: -> { 12_345 })
    end

    def deterministic_clock
      values = [ 100.0, 100.007 ]
      -> { values.shift || 100.007 }
    end

    def digital_pdf(text)
      <<~PDF.b
        %PDF-1.7
        1 0 obj << /Type /Page /MediaBox [0 0 612 792] >> endobj
        2 0 obj << /Length 44 >> stream
        BT (#{text}) Tj ET
        endstream endobj
        %%EOF
      PDF
    end
  end
end
