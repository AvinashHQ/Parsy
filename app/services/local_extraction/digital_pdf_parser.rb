# frozen_string_literal: true

require "digest"

module LocalExtraction
  class DigitalPdfParser
    VERSION = "local-digital-pdf-parser-ruby-0.1.0"
    DEFAULT_OPTIONS = {
      parser: "deterministic_pdf_text_boundary",
      stream_scan_limit_bytes: 512.kilobytes,
      max_pages: 100
    }.freeze

    def initialize(options: {}, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, memory_probe: -> { current_memory_kb })
      @options = DEFAULT_OPTIONS.merge(symbolize(options)).freeze
      @clock = clock
      @memory_probe = memory_probe
    end

    def call(bytes:, metadata: {}) = parse(bytes:, metadata:)

    def parse(bytes:, metadata: {})
      started_at = clock.call
      input = bytes.to_s.b
      warnings = []
      result = build_pdf_result(input, metadata, warnings)
      attach_runtime_metadata(result, input, started_at)
    rescue StandardError
      attach_runtime_metadata(PageDocument.failed(error_code: "PDF_PARSER_FAILURE", metadata: {}, warnings: warnings), input || "".b, started_at || clock.call)
    end

    private

    attr_reader :options, :clock, :memory_probe

    def build_pdf_result(input, metadata, warnings)
      return failure("UNSUPPORTED_MEDIA_TYPE", warnings) unless input.start_with?("%PDF-".b)
      return failure("PDF_CORRUPT", warnings) unless input.include?("%%EOF".b)
      return failure("PDF_ENCRYPTED", warnings) if encrypted?(input)

      pages = pages_from_metadata(metadata)
      pages = pages_from_pdf_bytes(input) if pages.empty?
      return failure("SCANNED_PDF_REQUIRES_OCR", warnings) if pages.empty?

      PageDocument.accepted(pages:, source_type: "digital_pdf", metadata: {}, warnings: warnings + pages.flat_map(&:quality_warnings))
    end

    def failure(code, warnings)
      PageDocument.failed(error_code: code, metadata: {}, warnings: warnings)
    end

    def attach_runtime_metadata(result, input, started_at)
      runtime_ms = ((clock.call - started_at) * 1000).round(3)
      metadata = base_metadata(input, runtime_ms)

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

    def base_metadata(input, runtime_ms)
      {
        parser: "digital_pdf",
        parser_version: VERSION,
        options: options,
        runtime_ms: runtime_ms,
        peak_memory_kb: Integer(memory_probe.call),
        input_byte_size: input.bytesize,
        source_sha256: Digest::SHA256.hexdigest(input)
      }
    end

    def pages_from_metadata(metadata)
      Array(fetch(metadata, :pages)).first(options.fetch(:max_pages)).filter_map.with_index(1) do |page, index|
        page_hash = symbolize(page)
        text = page_hash[:text].to_s
        layout = Array(page_hash[:layout])
        if layout.empty? && !text.empty?
          layout = [ { id: "p#{index}-b1", kind: "text", text: text, bbox: page_hash[:bbox] || [ 0, 0, page_hash[:width] || 0, page_hash[:height] || 0 ] } ]
        end

        evidence = Array(page_hash[:evidence])
        if evidence.empty? && !text.empty?
          evidence = [ { id: "p#{index}-e1", kind: "text", text: text, bbox: page_hash[:bbox] || [ 0, 0, page_hash[:width] || 0, page_hash[:height] || 0 ], source: "digital_pdf" } ]
        end

        PageDocument.page(
          number: page_hash[:number] || index,
          width: page_hash[:width] || 612,
          height: page_hash[:height] || 792,
          rotation: page_hash[:rotation] || 0,
          layout: layout,
          tables: Array(page_hash[:tables]),
          evidence: evidence,
          quality_warnings: quality_warnings(page_hash)
        )
      end
    end

    def pages_from_pdf_bytes(input)
      text_values = extract_text(input.byteslice(0, options.fetch(:stream_scan_limit_bytes)))
      return [] if text_values.empty?

      width, height = media_box(input)
      table_rows = table_rows_from_text(text_values)
      layout = text_values.each_with_index.map do |text, index|
        { id: "p1-b#{index + 1}", kind: "text", text: text, bbox: [ 0, index * 12, width, (index + 1) * 12 ] }
      end
      evidence = text_values.each_with_index.map do |text, index|
        { id: "p1-e#{index + 1}", kind: "text", text: text, bbox: [ 0, index * 12, width, (index + 1) * 12 ], source: "digital_pdf" }
      end
      tables = table_rows.empty? ? [] : [ { id: "p1-t1", bbox: [ 0, 0, width, height ], rows: table_rows } ]

      [ PageDocument.page(number: 1, width:, height:, rotation: 0, layout:, tables:, evidence:) ]
    end

    def extract_text(sample)
      values = []
      sample.to_s.scan(/\(((?:\\.|[^\\)])*)\)\s*Tj/n) { |match| values << pdf_unescape(match.first) }
      sample.to_s.scan(/\[((?:.|\n)*?)\]\s*TJ/n) do |match|
        match.first.scan(/\(((?:\\.|[^\\)])*)\)/n) { |inner| values << pdf_unescape(inner.first) }
      end
      values.map { |value| value.gsub(/\s+/, " ").strip }.reject(&:empty?).uniq
    end

    def pdf_unescape(value)
      value.to_s.gsub(/\\([nrtbf()\\])/) do
        case Regexp.last_match(1)
        when "n" then "\n"
        when "r" then "\r"
        when "t" then "\t"
        when "b" then "\b"
        when "f" then "\f"
        else Regexp.last_match(1)
        end
      end
    end

    def table_rows_from_text(values)
      values.each_with_object([]) do |value, rows|
        next unless value.include?("|")

        row = value.split("|").map(&:strip)
        rows << row if row.length > 1
      end
    end

    def media_box(input)
      match = input.match(%r{/MediaBox\s*\[\s*(?:-?\d+(?:\.\d+)?\s+){2}(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\]}n)
      return [ 612, 792 ] unless match

      [ Float(match[1]).round, Float(match[2]).round ]
    rescue ArgumentError
      [ 612, 792 ]
    end

    def encrypted?(input)
      sample = input.byteslice(0, [ input.bytesize, 256.kilobytes ].min).to_s
      sample.include?("/Encrypt") || sample.include?("/EncryptMetadata")
    end

    def quality_warnings(page_hash)
      warnings = []
      warnings << "ROTATED_PAGE" if page_hash[:rotation].to_i % 360 != 0
      warnings << "SKEWED_PAGE" if page_hash[:skew_degrees].to_f.abs >= 2.0
      warnings << "BLURRED_IMAGE" if page_hash.key?(:blur_score) && page_hash[:blur_score].to_f < 0.5
      warnings
    end

    def fetch(hash, key)
      return nil unless hash.respond_to?(:[])

      hash[key] || hash[key.to_s]
    end

    def symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(key, value), result| result[key.to_sym] = value }
    end

    def self.current_memory_kb
      rss_pages = `ps -o rss= -p #{Process.pid}`.to_i
      rss_pages.positive? ? rss_pages : 0
    rescue StandardError
      0
    end

    def current_memory_kb = self.class.current_memory_kb
  end
end
