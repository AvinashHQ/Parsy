# frozen_string_literal: true

module Extraction
  # Runs semantic extraction for a persisted, source-bearing document and
  # turns the result into a candidate revision (on success) or a recorded,
  # non-destructive failure state (otherwise).
  #
  # This is the bridge the upload flow was missing: intake persists the source
  # and routes the document, then ProcessDocumentJob calls this service to
  # actually populate the review record. It is defensive by design — any
  # extraction error degrades to a safe, retryable document state rather than
  # crashing the job.
  class DocumentExtractor
    EXTRACTION_ERROR = "EXTRACTION_ERROR"
    SOURCE_UNAVAILABLE = "SOURCE_UNAVAILABLE"
    INVALID_PROVIDER = "INVALID_EXTRACTION_PROVIDER"
    IMAGE_MIME_TYPES = %w[image/jpeg image/png].freeze
    # PARSY_EXTRACTION_PROVIDER (ADR-026): blank/unset selects the documented
    # cloud default; these values opt into the local fallback; anything else is
    # a misconfiguration and fails safe (see #call) rather than silently
    # guessing a provider.
    LOCAL_PROVIDER_VALUES = %w[ollama local local_open_source].freeze
    CLOUD_PROVIDER_VALUES = %w[gemini cloud].freeze
    CLOUD_PROVIDER_VERSION = "gemini-cloud-v1"
    CLOUD_PROVIDER_TIMEOUT_MS = 120_000

    def self.call(document:, **options)
      new(document:, **options).call
    end

    def initialize(document:, actor: "system", inspector: Intake::UploadInspector.new,
                   pdf_parser: LocalExtraction::DigitalPdfParser.new,
                   ocr_adapter: LocalExtraction::OcrEvidenceAdapter.new(client: LocalExtraction::GlmOcrClient.new),
                   pdf_rasterizer: LocalExtraction::PdfRasterizer.new, route_composer: nil)
      @document = document
      @actor = actor
      @inspector = inspector
      @pdf_parser = pdf_parser
      @ocr_adapter = ocr_adapter
      @pdf_rasterizer = pdf_rasterizer
      @route_composer = route_composer || self.class.default_route_composer
    end

    # nil when PARSY_EXTRACTION_PROVIDER is misconfigured — #call fails safe
    # rather than guessing a provider (see configured_provider).
    def self.default_route_composer
      adapter = default_semantic_adapter
      adapter && LocalExtraction::RouteComposer.new(semantic_adapter: adapter)
    end

    # ADR-026: Google Gemini (cloud) is the MVP default; PARSY_EXTRACTION_PROVIDER
    # opts into the local qwen3-vl/Ollama fallback. Both routes reuse
    # LocalExtraction::QwenSemanticAdapter's idempotency/repair/provenance
    # machinery — see that class for why a cloud client fits the same adapter.
    def self.default_semantic_adapter
      case configured_provider
      when :local
        LocalExtraction::QwenSemanticAdapter.new(client: LocalExtraction::OllamaClient.new)
      when :cloud
        LocalExtraction::QwenSemanticAdapter.new(
          client: RemoteVision::GeminiClient.new,
          provider_id: RemoteVision::GeminiClient::PROVIDER,
          provider_version: CLOUD_PROVIDER_VERSION,
          model: RemoteVision::GeminiClient::DEFAULT_MODEL,
          runtime: "gemini_cloud",
          quantization: "n/a",
          device: "managed_cloud",
          timeout_ms: CLOUD_PROVIDER_TIMEOUT_MS
        )
      end
    end

    # :invalid (any non-blank value that isn't a recognized cloud/local alias)
    # falls through to nil rather than a client, on purpose: silently routing a
    # typo'd config value to the cloud provider would spend real API calls the
    # operator never intended.
    def self.configured_provider
      value = ENV["PARSY_EXTRACTION_PROVIDER"].to_s.strip.downcase
      return :cloud if value.empty? || CLOUD_PROVIDER_VALUES.include?(value)
      return :local if LOCAL_PROVIDER_VALUES.include?(value)

      :invalid
    end

    def call
      return record_failure(INVALID_PROVIDER, status: "failed") if route_composer.nil?
      return record_failure(SOURCE_UNAVAILABLE, status: "failed") unless source_bytes

      inspection = inspector.inspect_bytes(source_bytes, filename: source_filename, content_type: source_content_type)
      parser_result = parser_output(inspection)
      image_bytes = visual_bytes(inspection, parser_result)
      result = route_composer.call(
        inspection:,
        parser_output: parser_result,
        ocr_output: ocr_output(image_bytes),
        images_bytes: image_bytes ? [ image_bytes ] : []
      )

      if result.success?
        ingest_candidate(result, inspection)
      else
        record_safe_failure(result)
      end
    rescue StandardError => error
      Rails.logger.error("[DocumentExtractor] #{error.class}: #{error.message}") if defined?(Rails)
      record_failure(EXTRACTION_ERROR, status: "failed")
    end

    private

    attr_reader :document, :actor, :inspector, :pdf_parser, :ocr_adapter, :pdf_rasterizer, :route_composer

    def ingest_candidate(result, inspection)
      original_route = document.route
      ingested = Review::ProviderResultIngester.call(
        batch: document.batch,
        source_sha256: document.source_sha256,
        result: result,
        source_metadata: ingest_metadata(inspection),
        actor: actor
      )
      # Preserve the intake-detected route if the model omitted source.route.
      ingested.update!(route: original_route) if ingested.route.blank? && original_route.present?
      ingested
    end

    def record_safe_failure(result)
      failure = result.failure
      status = %w[needs_review failed quarantined].include?(failure&.status) ? failure.status : "needs_review"
      record_failure(result.error_code || EXTRACTION_ERROR, status:, provenance: result.to_h)
    end

    def record_failure(code, status:, provenance: {})
      document.update!(
        status: status,
        processing_provenance: (document.processing_provenance || {}).merge(
          "extraction" => { "error_code" => code, "detail" => provenance }.compact
        )
      )
      document.events.create!(
        batch: document.batch,
        actor: actor,
        action: "extraction_#{status}",
        reason: "automated extraction",
        metadata: { error_code: code, route: document.route }.compact
      )
      document.batch.refresh_status!
      document
    end

    def ingest_metadata(inspection)
      {
        "filename" => source_filename,
        "mime_type" => inspection.sniffed_mime_type,
        "page_count" => inspection.metadata[:page_count] || inspection.metadata["page_count"],
        "route_profile_version" => inspection.detection&.version
      }.compact
    end

    def parser_output(inspection)
      return {} unless inspection.sniffed_mime_type == "application/pdf"

      result = pdf_parser.call(bytes: source_bytes)
      return {} unless result.accepted?

      pages = Array(result.document&.pages).map do |page|
        { "number" => page.number, "text" => page_text(page) }
      end
      {
        "version" => LocalExtraction::DigitalPdfParser::VERSION,
        "page_count" => pages.size,
        "pages" => pages,
        "text" => pages.map { |page| page["text"] }.reject(&:blank?).join("\n")
      }
    rescue StandardError
      {}
    end

    # Raw page bytes for the OCR/vision stage. A raster image is used as-is;
    # a PDF is rasterized only when it has no usable digital text (a
    # genuinely scanned/photographed document) so a digital PDF that already
    # parsed cleanly doesn't pay for an extra OCR+vision round trip.
    def visual_bytes(inspection, parser_result)
      case inspection.sniffed_mime_type
      when *IMAGE_MIME_TYPES
        source_bytes
      when "application/pdf"
        parser_result["text"].present? ? nil : pdf_rasterizer.call(bytes: source_bytes)
      end
    end

    def ocr_output(image_bytes)
      return {} unless image_bytes

      result = ocr_adapter.call(bytes: image_bytes)
      return {} unless result.accepted?

      pages = Array(result.document&.pages).map do |page|
        { "number" => page.number, "text" => page_text(page) }
      end
      {
        "version" => LocalExtraction::OcrEvidenceAdapter::VERSION,
        "page_count" => pages.size,
        "pages" => pages,
        "text" => pages.map { |page| page["text"] }.reject(&:blank?).join("\n")
      }
    rescue StandardError
      {}
    end

    def page_text(page)
      Array(page.layout).map(&:text).reject(&:blank?).join("\n")
    end

    def source_bytes
      return @source_bytes if defined?(@source_bytes)

      @source_bytes = document.source_file.attached? ? document.source_file.download.to_s.b : nil
    end

    def source_filename
      document.source_file.attached? ? document.source_file.filename.to_s : "document"
    end

    def source_content_type
      document.source_file.attached? ? document.source_file.content_type : nil
    end
  end
end
