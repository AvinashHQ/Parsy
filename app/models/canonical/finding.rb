# frozen_string_literal: true

module Canonical
  class Finding
    SEVERITIES = %w[INFO LOW MEDIUM HIGH CRITICAL].freeze

    attr_reader :code, :severity, :behavior, :field_paths, :message, :observed, :calculated, :tolerance, :pack_id, :pack_version, :metadata

    def initialize(code:, severity:, field_paths:, message:, behavior: nil, observed: nil, calculated: nil, tolerance: nil, pack_id: nil, pack_version: nil, metadata: {})
      raise ArgumentError, "unknown finding severity #{severity}" unless SEVERITIES.include?(severity)

      @code = code
      @severity = severity
      @behavior = behavior
      @field_paths = Array(field_paths).freeze
      @message = message
      @observed = observed
      @calculated = calculated
      @tolerance = tolerance
      @pack_id = pack_id
      @pack_version = pack_version
      @metadata = metadata.freeze
    end

    def critical? = severity == "CRITICAL"
    def high? = severity == "HIGH"

    def to_h
      {
        code: code,
        severity: severity,
        behavior: behavior,
        field_paths: field_paths,
        message: message,
        observed: observed,
        calculated: calculated,
        tolerance: tolerance,
        pack_id: pack_id,
        pack_version: pack_version,
        metadata: metadata
      }.compact
    end
  end
end
