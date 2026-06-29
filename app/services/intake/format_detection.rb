# frozen_string_literal: true

module Intake
  class FormatDetection
    EmbeddedPayload = Data.define(:filename, :profile, :namespace, :media_type, :byte_size, :sha256) do
      def to_h
        {
          filename: filename,
          profile: profile,
          namespace: namespace,
          media_type: media_type,
          byte_size: byte_size,
          sha256: sha256
        }.compact
      end
    end

    attr_reader :family, :profile, :version, :route, :mvp_status, :confidence, :embedded_payloads, :warnings, :quarantine_reason

    def initialize(family:, route:, profile: nil, version: nil, mvp_status: nil, confidence: :deterministic, embedded_payloads: [], warnings: [], quarantine_reason: nil)
      @family = family.to_s
      @route = route.to_s
      @profile = profile
      @version = version
      @mvp_status = mvp_status
      @confidence = confidence.to_s
      @embedded_payloads = embedded_payloads.freeze
      @warnings = warnings.freeze
      @quarantine_reason = quarantine_reason
    end

    def quarantine? = route == "quarantine"
    def structured? = %w[ubl cii peppol_bis xrechnung fatturapa india_einvoice brazil_nfe unknown_structured].include?(family)
    def embedded_structured? = embedded_payloads.any?

    def to_h
      {
        family: family,
        profile: profile,
        version: version,
        route: route,
        mvp_status: mvp_status,
        confidence: confidence,
        embedded_payloads: embedded_payloads.map(&:to_h),
        warnings: warnings,
        quarantine_reason: quarantine_reason
      }.compact
    end
  end
end
