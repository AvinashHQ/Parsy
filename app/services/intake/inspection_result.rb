# frozen_string_literal: true

module Intake
  class InspectionResult
    attr_reader :status, :sha256, :byte_size, :sniffed_mime_type, :declared_content_type, :filename, :detection, :rejection_code, :message, :metadata

    def initialize(status:, sha256:, byte_size:, sniffed_mime_type:, declared_content_type:, filename:, detection:, rejection_code: nil, message: nil, metadata: {})
      @status = status.to_s
      @sha256 = sha256
      @byte_size = byte_size
      @sniffed_mime_type = sniffed_mime_type
      @declared_content_type = declared_content_type
      @filename = filename
      @detection = detection
      @rejection_code = rejection_code
      @message = message
      @metadata = metadata.freeze
    end

    def accepted? = status == "accepted"
    def rejected? = status == "rejected"
    def quarantined? = status == "quarantined"

    def route = detection&.route

    def observability
      {
        status: status,
        route: detection&.route,
        family: detection&.family,
        profile: detection&.profile,
        mvp_status: detection&.mvp_status,
        rejection_code: rejection_code,
        byte_size: byte_size,
        sniffed_mime_type: sniffed_mime_type,
        declared_content_type: declared_content_type,
        content_type_mismatch: content_type_mismatch?,
        embedded_payload_count: detection&.embedded_payloads&.length.to_i,
        warning_codes: detection&.warnings || [],
        metadata: metadata
      }.compact
    end

    def to_h
      {
        status: status,
        sha256: sha256,
        byte_size: byte_size,
        sniffed_mime_type: sniffed_mime_type,
        declared_content_type: declared_content_type,
        filename: filename,
        detection: detection&.to_h,
        rejection_code: rejection_code,
        message: message,
        metadata: metadata
      }.compact
    end

    private

    def content_type_mismatch?
      declared_content_type.present? && sniffed_mime_type.present? && declared_content_type != sniffed_mime_type
    end
  end
end
