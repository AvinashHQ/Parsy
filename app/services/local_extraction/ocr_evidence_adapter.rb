# frozen_string_literal: true

require "digest"

module LocalExtraction
  class OcrEvidenceAdapter
    VERSION = "local-ocr-evidence-adapter-ruby-0.1.0"
    DEFAULT_OPTIONS = {
      adapter: "deterministic_ocr_boundary",
      min_blur_score: 0.5,
      max_skew_degrees: 2.0,
      allow_tiff: false
    }.freeze

    def initialize(client:, options: {}, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, memory_probe: -> { DigitalPdfParser.current_memory_kb })
      @client = client
      @options = DEFAULT_OPTIONS.merge(symbolize(options)).freeze
      @clock = clock
      @memory_probe = memory_probe
    end

    def call(bytes:, metadata: {}) = extract(bytes:, metadata:)

    def extract(bytes:, metadata: {})
      started_at = clock.call
      input = bytes.to_s.b
      mime_type = sniff(input)
      warnings = quality_warnings(metadata).dup

      result = build_ocr_result(input, metadata, mime_type, warnings)
      attach_runtime_metadata(result, input, mime_type, started_at)
    rescue StandardError
      attach_runtime_metadata(PageDocument.failed(error_code: "OCR_ADAPTER_FAILURE", metadata: {}, warnings: warnings || []), input || "".b, mime_type || "unknown", started_at || clock.call)
    end

    private

    attr_reader :client, :options, :clock, :memory_probe

    def build_ocr_result(input, metadata, mime_type, warnings)
      return PageDocument.failed(error_code: "UNSUPPORTED_MEDIA_TYPE", metadata: {}, warnings: warnings) if mime_type == "unknown"

      if mime_type == "image/tiff" && !options.fetch(:allow_tiff)
        return PageDocument.failed(error_code: "TIFF_REQUIRES_TRANSCODE", metadata: {}, warnings: warnings + [ "TIFF_INPUT" ])
      end

      response = normalize_response(call_client(input, metadata))
      warnings.concat(quality_warnings(response))
      pages = pages_from_response(response)
      warnings.concat(pages.flat_map(&:quality_warnings))
      return PageDocument.failed(error_code: "OCR_EMPTY_RESULT", metadata: {}, warnings: warnings) if pages.empty?

      PageDocument.accepted(pages:, source_type: "ocr", metadata: response_metadata(response), warnings: warnings)
    end

    def attach_runtime_metadata(result, input, mime_type, started_at)
      runtime_ms = ((clock.call - started_at) * 1000).round(3)
      metadata = base_metadata(input, mime_type, runtime_ms).merge(result.metadata || {})

      if result.accepted?
        PageDocument.accepted(
          pages: result.document.pages,
          source_type: result.document.source_type,
          metadata: metadata,
          warnings: result.warnings
        )
      else
        PageDocument.failed(error_code: result.error_code, metadata: metadata, warnings: result.warnings)
      end
    end

    def base_metadata(input, mime_type, runtime_ms)
      {
        adapter: "ocr_evidence",
        adapter_version: VERSION,
        options: options,
        runtime_ms: runtime_ms,
        peak_memory_kb: Integer(memory_probe.call),
        input_byte_size: input.bytesize,
        input_mime_type: mime_type,
        source_sha256: Digest::SHA256.hexdigest(input)
      }
    end

    def response_metadata(response)
      raw_metadata = symbolize(response[:metadata] || {})
      {
        ocr_version: response[:version] || raw_metadata[:version] || client_version,
        ocr_options: symbolize(raw_metadata[:options] || {}),
        ocr_runtime: raw_metadata[:runtime],
        ocr_peak_memory_kb: raw_metadata[:peak_memory_kb]
      }.compact
    end

    def call_client(input, metadata)
      if client.respond_to?(:call)
        client.call(bytes: input, metadata: metadata, options: options)
      elsif client.respond_to?(:extract)
        client.extract(bytes: input, metadata: metadata, options: options)
      else
        raise ArgumentError, "OCR client must respond to call or extract"
      end
    end

    def pages_from_response(response)
      Array(response[:pages]).filter_map.with_index(1) do |page, index|
        page_hash = symbolize(page)
        text = page_hash[:text].to_s
        layout = Array(page_hash[:layout])
        if layout.empty? && !text.empty?
          layout = [ { id: "p#{index}-b1", kind: "text", text: text, confidence: page_hash[:confidence], bbox: page_hash[:bbox] || [ 0, 0, page_hash[:width] || 0, page_hash[:height] || 0 ] } ]
        end

        evidence = Array(page_hash[:evidence])
        if evidence.empty? && !text.empty?
          evidence = [ { id: "p#{index}-e1", kind: "ocr_text", text: text, bbox: page_hash[:bbox] || [ 0, 0, page_hash[:width] || 0, page_hash[:height] || 0 ], source: "ocr" } ]
        end

        PageDocument.page(
          number: page_hash[:number] || index,
          width: page_hash[:width] || 0,
          height: page_hash[:height] || 0,
          rotation: page_hash[:rotation] || 0,
          layout: layout,
          tables: Array(page_hash[:tables]),
          evidence: evidence,
          quality_warnings: quality_warnings(page_hash)
        )
      end
    end

    def normalize_response(response)
      case response
      when Hash
        symbolize(response)
      else
        raise ArgumentError, "OCR client response must be a hash"
      end
    end

    def quality_warnings(attributes)
      values = symbolize(attributes)
      warnings = Array(values[:warnings]).map(&:to_s)
      warnings << "BLURRED_IMAGE" if values.key?(:blur_score) && values[:blur_score].to_f < options.fetch(:min_blur_score)
      warnings << "ROTATED_PAGE" if values[:rotation].to_i % 360 != 0
      warnings << "SKEWED_PAGE" if values.key?(:skew_degrees) && values[:skew_degrees].to_f.abs >= options.fetch(:max_skew_degrees)
      warnings.map(&:upcase).uniq
    end

    def sniff(input)
      return "application/pdf" if input.start_with?("%PDF-".b)
      return "image/jpeg" if input.byteslice(0, 3) == "\xFF\xD8\xFF".b
      return "image/png" if input.start_with?("\x89PNG\r\n\x1A\n".b)
      return "image/tiff" if input.start_with?("II*\x00".b) || input.start_with?("MM\x00*".b)

      "unknown"
    end

    def client_version
      client.version if client.respond_to?(:version)
    end

    def symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(key, value), result| result[key.to_sym] = value }
    end
  end
end
