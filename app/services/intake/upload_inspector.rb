# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Intake
  class UploadInspector
    DEFAULT_MAX_BYTES = 20.megabytes
    XML_SCAN_LIMIT = 128.kilobytes
    MAX_PDF_PAGES = 50
    MAX_XML_BYTES = 1.megabyte
    MAX_XML_TAGS = 5_000

    Sniff = Data.define(:mime_type, :kind)

    def initialize(max_bytes: DEFAULT_MAX_BYTES, registry_path: Rails.root.join("config/format_registry.yml"))
      @max_bytes = max_bytes
      @registry = YAML.safe_load(Pathname(registry_path).read, aliases: false).deep_stringify_keys
    end

    def call(io:, filename: nil, content_type: nil)
      upload = read_limited_io(io)
      inspect_bytes(upload.fetch(:bytes), filename: filename, content_type: content_type, forced_byte_size: upload.fetch(:byte_size), forced_sha256: upload.fetch(:sha256))
    end

    def inspect(path:, filename: nil, content_type: nil)
      path = Pathname(path)
      return reject_oversized_path(path, filename: filename || path.basename.to_s, content_type: content_type) if path.size > max_bytes

      bytes = path.binread
      inspect_bytes(bytes, filename: filename || path.basename.to_s, content_type: content_type)
    end

    def inspect_bytes(bytes, filename:, content_type: nil, forced_byte_size: nil, forced_sha256: nil)
      bytes = bytes.to_s.b
      sha256 = forced_sha256 || Digest::SHA256.hexdigest(bytes)
      byte_size = forced_byte_size || bytes.bytesize
      return reject(sha256: sha256, byte_size: byte_size, sniff: Sniff.new(nil, :unknown), filename: filename, content_type: content_type, code: "MALICIOUS_FILENAME", message: "filename contains unsafe path characters") if unsafe_filename?(filename)

      sniff = sniff(bytes)

      return reject(sha256: sha256, byte_size: byte_size, sniff: sniff, filename: filename, content_type: content_type, code: "FILE_TOO_LARGE", message: "file exceeds maximum allowed size") if byte_size > max_bytes
      return reject(sha256: sha256, byte_size: byte_size, sniff: sniff, filename: filename, content_type: content_type, code: "UNSUPPORTED_BINARY_FORMAT", message: "file type is unsupported") if sniff.kind == :unknown
      detection = detect(bytes, sniff)
      status = detection.quarantine? ? "quarantined" : "accepted"
      InspectionResult.new(
        status: status,
        sha256: sha256,
        byte_size: byte_size,
        sniffed_mime_type: sniff.mime_type,
        declared_content_type: content_type,
        filename: filename,
        detection: detection,
        rejection_code: detection.quarantine_reason,
        message: detection.quarantine_reason,
        metadata: content_free_metadata(bytes, sniff, detection)
      )
    end

    private

    attr_reader :max_bytes, :registry
    def read_limited_io(io)
      io.binmode if io.respond_to?(:binmode)
      io.rewind if io.respond_to?(:rewind)
      digest = Digest::SHA256.new
      byte_size = 0
      kept = String.new(encoding: Encoding::BINARY)

      while (chunk = io.read(64.kilobytes))
        chunk = chunk.b
        digest.update(chunk)
        byte_size += chunk.bytesize
        kept << chunk if kept.bytesize < max_bytes
        kept = kept.byteslice(0, max_bytes) if kept.bytesize > max_bytes
      end

      { bytes: kept, byte_size: byte_size, sha256: digest.hexdigest }
    end

    def reject_oversized_path(path, filename:, content_type:)
      sha256 = Digest::SHA256.file(path).hexdigest
      reject(sha256: sha256, byte_size: path.size, sniff: Sniff.new(nil, :unknown), filename: filename, content_type: content_type, code: "FILE_TOO_LARGE", message: "file exceeds maximum allowed size")
    end


    def reject(sha256:, byte_size:, sniff:, filename:, content_type:, code:, message:)
      InspectionResult.new(
        status: "rejected",
        sha256: sha256,
        byte_size: byte_size,
        sniffed_mime_type: sniff.mime_type,
        declared_content_type: content_type,
        filename: filename,
        detection: FormatDetection.new(family: "unknown_visual", route: "quarantine", confidence: :deterministic, quarantine_reason: code),
        rejection_code: code,
        message: message,
        metadata: {}
      )
    end

    def unsafe_filename?(filename)
      filename.to_s.match?(%r{[\/\\\0]}) || filename.to_s.include?("..")
    end

    def sniff(bytes)
      return Sniff.new("application/pdf", :pdf) if bytes.start_with?("%PDF-")
      return Sniff.new("image/jpeg", :jpeg) if bytes.byteslice(0, 3) == "\xFF\xD8\xFF".b
      return Sniff.new("image/png", :png) if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
      return Sniff.new("image/tiff", :tiff) if bytes.start_with?("II*\x00".b) || bytes.start_with?("MM\x00*".b)

      prefix = bytes.byteslice(0, XML_SCAN_LIMIT).to_s.sub(/\A\xEF\xBB\xBF/n, "").lstrip
      return Sniff.new("application/xml", :xml) if prefix.start_with?("<")
      return Sniff.new("application/json", :json) if prefix.start_with?("{", "[")

      Sniff.new(nil, :unknown)
    end

    def detect(bytes, sniff)
      case sniff.kind
      when :pdf
        detect_pdf(bytes)
      when :jpeg
        registry_detection("image_jpeg")
      when :png
        registry_detection("image_png")
      when :tiff
        registry_detection("image_tiff")
      when :xml
        detect_xml(bytes)
      when :json
        quarantine("unknown_structured", "UNSUPPORTED_STRUCTURED_FORMAT")
      else
        quarantine("unknown_visual", "UNSUPPORTED_BINARY_FORMAT")
      end
    end

    def detect_pdf(bytes)
      return quarantine("visual_pdf", "ENCRYPTED_PDF") if encrypted_pdf?(bytes)
      return quarantine("visual_pdf", "CORRUPT_PDF") unless bytes.include?("%%EOF")
      return quarantine("visual_pdf", "PDF_PAGE_LIMIT_EXCEEDED") if pdf_page_count(bytes) > MAX_PDF_PAGES

      payloads = embedded_payloads(bytes)
      if payloads.any?
        registry_detection("factur_x_zugferd", embedded_payloads: payloads)
      else
        registry_detection("visual_pdf")
      end
    end

    def detect_xml(bytes)
      return quarantine("unknown_structured", "XML_TOO_LARGE") if bytes.bytesize > MAX_XML_BYTES

      sample = bytes.byteslice(0, XML_SCAN_LIMIT).to_s
      return quarantine("unknown_structured", "XML_ENTITY_EXPANSION_RISK") if sample.match?(/<!DOCTYPE|<!ENTITY|SYSTEM\\s+[\"']https?:/i)
      return quarantine("unknown_structured", "XML_NESTING_LIMIT_EXCEEDED") if sample.scan(/<[^!?\/][^>]*>/).size > MAX_XML_TAGS
      return registry_detection("oasis_ubl_invoice") if sample.include?("urn:oasis:names:specification:ubl:schema:xsd:Invoice-2") || sample.include?("urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2")
      return registry_detection("uncefact_cii") if sample.include?("CrossIndustryInvoice") || sample.include?("urn:un:unece:uncefact:data:standard:CrossIndustryInvoice")

      quarantine("unknown_structured", "UNSUPPORTED_STRUCTURED_FORMAT")
    end

    def registry_detection(format_id, embedded_payloads: [])
      format = registry.fetch("formats").find { |entry| entry.fetch("id") == format_id }
      raise KeyError, "unknown format #{format_id}" unless format

      FormatDetection.new(
        family: format.fetch("family"),
        profile: format.fetch("id"),
        version: registry.fetch("version"),
        route: format.fetch("route"),
        mvp_status: format.fetch("mvp_status"),
        confidence: :deterministic,
        embedded_payloads: embedded_payloads
      )
    end

    def quarantine(family, reason)
      FormatDetection.new(
        family: family,
        route: "quarantine",
        version: registry.fetch("version"),
        mvp_status: "unsupported",
        confidence: :deterministic,
        quarantine_reason: reason
      )
    end

    def encrypted_pdf?(bytes)
      head = bytes.byteslice(0, [ bytes.bytesize, 256.kilobytes ].min).to_s
      head.include?("/Encrypt") || head.include?("/EncryptMetadata")
    end

    def embedded_payloads(bytes)
      return [] unless bytes.include?("/EmbeddedFiles") || bytes.match?(/factur[-_ ]?x|zugferd/i)

      sample = bytes.byteslice(0, [ bytes.bytesize, 512.kilobytes ].min).to_s
      recognized = sample.match?(/factur[-_]?x\.xml|zugferd[-_]?invoice\.xml/i) || sample.include?("urn:factur-x") || sample.include?("urn:ferd:CrossIndustryDocument")
      return [] unless recognized

      xml_slice = sample[/<\?xml.*?(?:CrossIndustryInvoice|rsm:CrossIndustryInvoice|Invoice).*?>/m] || ""
      [ FormatDetection::EmbeddedPayload.new(
        filename: sample[/[A-Za-z0-9_.-]*(?:factur[-_]?x|zugferd)[A-Za-z0-9_.-]*\.xml/i] || "embedded-invoice.xml",
        profile: "factur_x_zugferd",
        namespace: xml_slice[/urn:[^\s"']+/, 0],
        media_type: "application/xml",
        byte_size: xml_slice.bytesize.zero? ? nil : xml_slice.bytesize,
        sha256: xml_slice.empty? ? nil : Digest::SHA256.hexdigest(xml_slice)
      ) ]
    end

    def pdf_page_count(bytes)
      [ bytes.scan(%r{/Type\s*/Page\b}).length, 1 ].max
    end

    def content_free_metadata(bytes, sniff, detection)
      metadata = {
        registry_version: registry.fetch("version"),
        magic_kind: sniff.kind.to_s,
        embedded_payload_count: detection.embedded_payloads.length
      }
      metadata[:page_count] = pdf_page_count(bytes) if sniff.kind == :pdf
      metadata
    end
  end
end
