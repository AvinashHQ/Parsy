# frozen_string_literal: true

module LocalExtraction
  class SafeFailure
    JSON_INVALID = "JSON_INVALID"
    SCHEMA_INVALID = "SCHEMA_INVALID"
    TIMEOUT = "TIMEOUT"
    OUT_OF_MEMORY = "OUT_OF_MEMORY"
    CORRUPT_DOCUMENT = "CORRUPT_DOCUMENT"
    UNSUPPORTED_ROUTE = "UNSUPPORTED_ROUTE"
    REPAIR_UNAVAILABLE = "REPAIR_UNAVAILABLE"

    CONTENT_FREE_METADATA_KEYS = %i[
      source_sha256 route family profile detection_version byte_size page_count
      parser_version ocr_version model model_revision quantization runtime
      prompt_sha256 device latency_ms idempotency_key repair_attempts error_code
      schema_error_count schema_error_pointers schema_error_types failure_kind
    ].freeze

    attr_reader :status, :code, :route, :metadata

    def self.for_code(code, route:, metadata: {})
      status =
        case code.to_s
        when CORRUPT_DOCUMENT
          "quarantined"
        when JSON_INVALID, SCHEMA_INVALID, Extraction::ProviderAdapter::REPAIR_LIMIT_EXCEEDED,
             Extraction::ProviderAdapter::REPAIR_PATH_NOT_ALLOWED, Extraction::ProviderAdapter::REPAIR_EMPTY_PATCH,
             REPAIR_UNAVAILABLE, UNSUPPORTED_ROUTE
          "needs_review"
        else
          "failed"
        end

      new(status:, code:, route:, metadata:)
    end

    def initialize(status:, code:, route:, metadata: {})
      @status = status.to_s
      @code = code.to_s
      @route = route.to_s
      @metadata = self.class.content_free(metadata)
    end

    def failed? = status == "failed"
    def quarantined? = status == "quarantined"
    def needs_review? = status == "needs_review"

    def to_h
      {
        status: status,
        code: code,
        route: route,
        metadata: metadata
      }.compact
    end

    def self.content_free(metadata)
      source = metadata.to_h if metadata.respond_to?(:to_h)
      source = {} unless source.is_a?(Hash)

      source.each_with_object({}) do |(key, value), sanitized|
        normalized_key = key.to_sym
        next unless CONTENT_FREE_METADATA_KEYS.include?(normalized_key)

        sanitized[normalized_key] = sanitize_value(value)
      end.freeze
    end

    def self.sanitize_value(value)
      case value
      when Hash
        content_free(value)
      when Array
        value.map { |item| sanitize_scalar(item) }.freeze
      else
        sanitize_scalar(value)
      end
    end

    def self.sanitize_scalar(value)
      case value
      when NilClass, TrueClass, FalseClass, Numeric, Symbol
        value
      else
        value.to_s
      end
    end
  end
end
