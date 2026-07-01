# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"

module Extraction
  class DocumentExtractorTest < ActiveSupport::TestCase
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")
    PDF_BYTES = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF".b

    # Stand-in for the local model client: returns canned JSON so the real
    # RouteComposer -> QwenSemanticAdapter -> ProviderAdapter path runs
    # deterministically without a live model.
    class FixtureClient
      attr_reader :requests

      def initialize(json_text:)
        @json_text = json_text
        @requests = []
      end

      def extract_invoice(request)
        @requests << request
        { json_text: @json_text, metadata: { latency_ms: 12 } }
      end

      def repair_invoice(_request) = { patch: {} }
    end

    # Stand-in for the OCR boundary client (LocalExtraction::GlmOcrClient in
    # production): records the bytes it was asked to OCR and returns canned text.
    class FixtureOcrClient
      attr_reader :calls

      def initialize(text:)
        @text = text
        @calls = []
      end

      def call(bytes:, metadata: {}, options: {})
        @calls << bytes
        { pages: [ { number: 1, text: @text } ] }
      end
    end

    # Stand-in for LocalExtraction::PdfRasterizer: records the bytes it was
    # asked to rasterize and returns canned PNG-shaped output without shelling
    # out to python3/pymupdf.
    class FixtureRasterizer
      attr_reader :calls

      def initialize(image_bytes:)
        @image_bytes = image_bytes
        @calls = []
      end

      def call(bytes:)
        @calls << bytes
        @image_bytes
      end
    end

    setup do
      @tenant = Tenant.create!(name: "Extractor Tenant", slug: "extractor-#{SecureRandom.hex(4)}")
      @batch = @tenant.review_batches.create!(name: "Extractor Batch")
    end

    test "successful extraction creates a candidate revision and populates the review record" do
      document = document_with_source("sha-success")

      Extraction::DocumentExtractor.call(document: document, route_composer: fixture_composer(canonical_json), **no_visual_content)

      document.reload
      assert document.current_revision.present?, "expected a candidate revision"
      assert_includes %w[needs_review ready_for_approval], document.status
      assert_equal "visual_model", document.route
      assert_equal 1, document.events.where(action: "candidate_created").count
    end

    test "schema-invalid model output degrades to needs_review without nuking the document" do
      document = document_with_source("sha-schema-invalid")

      Extraction::DocumentExtractor.call(document: document, route_composer: fixture_composer("{}"), **no_visual_content)

      document.reload
      assert_nil document.current_revision
      assert_equal "needs_review", document.status
      assert_equal "visual_model", document.route, "intake route must be preserved on failure"
      assert_equal "SCHEMA_INVALID", document.processing_provenance.dig("extraction", "error_code")
      assert_equal 1, document.events.where(action: "extraction_needs_review").count
    end

    test "unexpected extraction error degrades to a failed, retryable state" do
      document = document_with_source("sha-error")
      exploding = Object.new
      def exploding.call(**) = raise "model exploded"

      Extraction::DocumentExtractor.call(document: document, route_composer: exploding, **no_visual_content)

      document.reload
      assert_nil document.current_revision
      assert_equal "failed", document.status
      assert_equal "EXTRACTION_ERROR", document.processing_provenance.dig("extraction", "error_code")
      assert_equal 1, document.events.where(action: "extraction_failed").count
    end

    test "missing source file fails safely" do
      document = @batch.documents.create!(source_sha256: "sha-no-source", status: "needs_review", route: "visual_model")

      Extraction::DocumentExtractor.call(document: document, route_composer: fixture_composer(canonical_json), **no_visual_content)

      document.reload
      assert_equal "failed", document.status
      assert_equal "SOURCE_UNAVAILABLE", document.processing_provenance.dig("extraction", "error_code")
    end

    test "raw image upload runs OCR and forwards the page image to the semantic client" do
      image_bytes = "\x89PNG\r\n\x1A\n".b + ("fake-png-body" * 4).b
      document = @batch.documents.create!(source_sha256: "sha-image", status: "needs_review", route: "visual_model", source_format_family: "image")
      document.source_file.attach(io: StringIO.new(image_bytes), filename: "invoice.png", content_type: "image/png")

      semantic_client = FixtureClient.new(json_text: canonical_json)
      ocr_client = FixtureOcrClient.new(text: "OCR'd invoice text")
      rasterizer = FixtureRasterizer.new(image_bytes: nil)

      Extraction::DocumentExtractor.call(
        document: document,
        route_composer: LocalExtraction::RouteComposer.new(
          semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(client: semantic_client)
        ),
        ocr_adapter: LocalExtraction::OcrEvidenceAdapter.new(client: ocr_client),
        pdf_rasterizer: rasterizer
      )

      assert_equal [ image_bytes ], ocr_client.calls, "a raw image upload should be OCR'd directly without rasterization"
      assert_empty rasterizer.calls, "rasterization is only for PDFs"

      request = semantic_client.requests.first
      assert_equal [ image_bytes ], request.fetch(:images_bytes), "the semantic client should receive the page image bytes"
      assert_includes request.fetch(:ocr_output).fetch(:pages).first.fetch(:text), "OCR'd invoice text"
    end

    test "scanned PDF with no digital text is rasterized and OCR'd" do
      document = document_with_source("sha-scanned-pdf")
      rasterized_png = "\x89PNG\r\n\x1A\n".b + ("rendered-page".b * 4)

      semantic_client = FixtureClient.new(json_text: canonical_json)
      ocr_client = FixtureOcrClient.new(text: "scanned page text")
      rasterizer = FixtureRasterizer.new(image_bytes: rasterized_png)

      Extraction::DocumentExtractor.call(
        document: document,
        route_composer: LocalExtraction::RouteComposer.new(
          semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(client: semantic_client)
        ),
        ocr_adapter: LocalExtraction::OcrEvidenceAdapter.new(client: ocr_client),
        pdf_rasterizer: rasterizer
      )

      assert_equal [ PDF_BYTES ], rasterizer.calls, "a PDF with no digital text layer must be rasterized"
      assert_equal [ rasterized_png ], ocr_client.calls, "the rasterized page should be sent to OCR"
      assert_equal [ rasterized_png ], semantic_client.requests.first.fetch(:images_bytes)
    end

    test "digital PDF with extractable text skips rasterization and OCR" do
      document = document_with_source("sha-digital-pdf", bytes: digital_pdf_bytes)

      semantic_client = FixtureClient.new(json_text: canonical_json)
      ocr_client = FixtureOcrClient.new(text: "should not be called")
      rasterizer = FixtureRasterizer.new(image_bytes: "should not be called")

      Extraction::DocumentExtractor.call(
        document: document,
        route_composer: LocalExtraction::RouteComposer.new(
          semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(client: semantic_client)
        ),
        ocr_adapter: LocalExtraction::OcrEvidenceAdapter.new(client: ocr_client),
        pdf_rasterizer: rasterizer
      )

      assert_empty rasterizer.calls, "a digital PDF with a usable text layer should not be rasterized"
      assert_empty ocr_client.calls
      assert_empty semantic_client.requests.first.fetch(:images_bytes)
    end

    private

    def document_with_source(sha, bytes: PDF_BYTES)
      document = @batch.documents.create!(source_sha256: sha, status: "needs_review", route: "visual_model", source_format_family: "visual_pdf")
      document.source_file.attach(io: StringIO.new(bytes), filename: "invoice.pdf", content_type: "application/pdf")
      document
    end

    # PDF_BYTES has no Tj/TJ text-showing operators, so DigitalPdfParser
    # reports SCANNED_PDF_REQUIRES_OCR for it; this fixture instead carries a
    # minimal real text-showing operator so the digital-text path is exercised.
    def digital_pdf_bytes
      "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\nBT (Northstar Invoice INV-1) Tj ET\n%%EOF".b
    end

    # Tests that only care about the schema/status outcome, not the visual
    # pipeline, opt out of rasterization/OCR so they stay hermetic (no python3
    # subprocess, no Ollama network call).
    def no_visual_content
      { ocr_adapter: LocalExtraction::OcrEvidenceAdapter.new(client: FixtureOcrClient.new(text: "")), pdf_rasterizer: FixtureRasterizer.new(image_bytes: nil) }
    end

    def fixture_composer(json_text)
      LocalExtraction::RouteComposer.new(
        semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(client: FixtureClient.new(json_text: json_text))
      )
    end

    def canonical_json
      JSON.generate(JSON.parse(FIXTURE_PATH.read))
    end
  end

  # ADR-026 provider selection: PARSY_EXTRACTION_PROVIDER picks the semantic
  # client the default route composer wires up. Only inspects the constructed
  # adapter's client/provider_id/model — never calls out to a real API.
  class DocumentExtractorProviderSelectionTest < ActiveSupport::TestCase
    test "unset PARSY_EXTRACTION_PROVIDER selects the Gemini cloud default" do
      with_extraction_provider(nil) do
        adapter = DocumentExtractor.default_semantic_adapter

        assert_instance_of RemoteVision::GeminiClient, adapter.client
        assert_equal RemoteVision::GeminiClient::PROVIDER, adapter.provider_id
        assert_equal RemoteVision::GeminiClient::DEFAULT_MODEL, adapter.model
      end
    end

    test "PARSY_EXTRACTION_PROVIDER=ollama selects the local fallback" do
      with_extraction_provider("ollama") do
        adapter = DocumentExtractor.default_semantic_adapter

        assert_instance_of LocalExtraction::OllamaClient, adapter.client
        assert_equal "local_open_source", adapter.provider_id
        assert_equal "qwen3-vl:4b", adapter.model
      end
    end

    test "PARSY_EXTRACTION_PROVIDER=local and =LOCAL_OPEN_SOURCE also select the local fallback" do
      with_extraction_provider("local") { assert_instance_of LocalExtraction::OllamaClient, DocumentExtractor.default_semantic_adapter.client }
      with_extraction_provider("LOCAL_OPEN_SOURCE") { assert_instance_of LocalExtraction::OllamaClient, DocumentExtractor.default_semantic_adapter.client }
    end

    test "PARSY_EXTRACTION_PROVIDER=gemini and =cloud also select the cloud default explicitly" do
      with_extraction_provider("gemini") { assert_instance_of RemoteVision::GeminiClient, DocumentExtractor.default_semantic_adapter.client }
      with_extraction_provider("CLOUD") { assert_instance_of RemoteVision::GeminiClient, DocumentExtractor.default_semantic_adapter.client }
    end

    # #84's acceptance criterion: "unknown value fails safe with a clear error" —
    # NOT silently routed to the cloud provider, which would spend real API
    # calls on what is likely an operator typo.
    test "an unrecognized PARSY_EXTRACTION_PROVIDER value is nil, not a silent guess" do
      with_extraction_provider("bogus") do
        assert_equal :invalid, DocumentExtractor.configured_provider
        assert_nil DocumentExtractor.default_semantic_adapter
        assert_nil DocumentExtractor.default_route_composer
      end
    end

    test "default_route_composer wraps the selected adapter in a RouteComposer" do
      with_extraction_provider("ollama") do
        composer = DocumentExtractor.default_route_composer

        assert_instance_of LocalExtraction::RouteComposer, composer
        assert_instance_of LocalExtraction::OllamaClient, composer.semantic_adapter.client
      end
    end

    test "an unrecognized provider fails a real document safely instead of guessing or crashing" do
      tenant = Tenant.create!(name: "Invalid Provider Tenant", slug: "invalid-provider-#{SecureRandom.hex(4)}")
      batch = tenant.review_batches.create!(name: "Invalid Provider Batch")
      document = batch.documents.create!(source_sha256: "sha-invalid-provider", status: "needs_review", route: "visual_model")
      document.source_file.attach(io: StringIO.new("%PDF-1.7\n%%EOF".b), filename: "invoice.pdf", content_type: "application/pdf")

      with_extraction_provider("bogus") { DocumentExtractor.call(document: document) }

      document.reload
      assert_equal "failed", document.status
      assert_equal DocumentExtractor::INVALID_PROVIDER, document.processing_provenance.dig("extraction", "error_code")
      assert_equal 1, document.events.where(action: "extraction_failed").count
    end

    # #84's other acceptance criterion: "Missing key produces a safe failure,
    # not a crash or a leak." RemoteVision::GeminiClient::MissingApiKey isn't
    # rescued by QwenSemanticAdapter#extract, so it must propagate up to
    # DocumentExtractor#call's own StandardError rescue (MissingApiKey < GenerationError
    # < StandardError) to degrade safely instead of crashing ProcessDocumentJob.
    # Real GeminiClient with a blank key — fails closed before any network call.
    test "a missing GEMINI_API_KEY fails the document safely instead of crashing the job" do
      tenant = Tenant.create!(name: "Missing Key Tenant", slug: "missing-key-#{SecureRandom.hex(4)}")
      batch = tenant.review_batches.create!(name: "Missing Key Batch")
      document = batch.documents.create!(source_sha256: "sha-missing-key", status: "needs_review", route: "visual_model")
      document.source_file.attach(io: StringIO.new("%PDF-1.7\nBT (text) Tj ET\n%%EOF".b), filename: "invoice.pdf", content_type: "application/pdf")

      route_composer = LocalExtraction::RouteComposer.new(
        semantic_adapter: LocalExtraction::QwenSemanticAdapter.new(client: RemoteVision::GeminiClient.new(api_key: ""))
      )

      assert_nothing_raised { DocumentExtractor.call(document: document, route_composer: route_composer) }

      document.reload
      assert_equal "failed", document.status
      serialized = document.processing_provenance.to_s
      refute_includes serialized, "api_key"
      assert_equal 1, document.events.where(action: "extraction_failed").count
    end

    private

    def with_extraction_provider(value)
      original = ENV["PARSY_EXTRACTION_PROVIDER"]
      value.nil? ? ENV.delete("PARSY_EXTRACTION_PROVIDER") : ENV["PARSY_EXTRACTION_PROVIDER"] = value
      yield
    ensure
      original.nil? ? ENV.delete("PARSY_EXTRACTION_PROVIDER") : ENV["PARSY_EXTRACTION_PROVIDER"] = original
    end
  end
end
