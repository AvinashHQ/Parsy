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
      def initialize(json_text:)
        @json_text = json_text
      end

      def extract_invoice(_request) = { json_text: @json_text, metadata: { latency_ms: 12 } }
      def repair_invoice(_request) = { patch: {} }
    end

    setup do
      @tenant = Tenant.create!(name: "Extractor Tenant", slug: "extractor-#{SecureRandom.hex(4)}")
      @batch = @tenant.review_batches.create!(name: "Extractor Batch")
    end

    test "successful extraction creates a candidate revision and populates the review record" do
      document = document_with_source("sha-success")

      Extraction::DocumentExtractor.call(document: document, route_composer: fixture_composer(canonical_json))

      document.reload
      assert document.current_revision.present?, "expected a candidate revision"
      assert_includes %w[needs_review ready_for_approval], document.status
      assert_equal "visual_model", document.route
      assert_equal 1, document.events.where(action: "candidate_created").count
    end

    test "schema-invalid model output degrades to needs_review without nuking the document" do
      document = document_with_source("sha-schema-invalid")

      Extraction::DocumentExtractor.call(document: document, route_composer: fixture_composer("{}"))

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

      Extraction::DocumentExtractor.call(document: document, route_composer: exploding)

      document.reload
      assert_nil document.current_revision
      assert_equal "failed", document.status
      assert_equal "EXTRACTION_ERROR", document.processing_provenance.dig("extraction", "error_code")
      assert_equal 1, document.events.where(action: "extraction_failed").count
    end

    test "missing source file fails safely" do
      document = @batch.documents.create!(source_sha256: "sha-no-source", status: "needs_review", route: "visual_model")

      Extraction::DocumentExtractor.call(document: document, route_composer: fixture_composer(canonical_json))

      document.reload
      assert_equal "failed", document.status
      assert_equal "SOURCE_UNAVAILABLE", document.processing_provenance.dig("extraction", "error_code")
    end

    private

    def document_with_source(sha)
      document = @batch.documents.create!(source_sha256: sha, status: "needs_review", route: "visual_model", source_format_family: "visual_pdf")
      document.source_file.attach(io: StringIO.new(PDF_BYTES), filename: "invoice.pdf", content_type: "application/pdf")
      document
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
end
