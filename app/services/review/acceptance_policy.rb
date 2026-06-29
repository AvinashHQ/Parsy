# frozen_string_literal: true

module Review
  class AcceptancePolicy
    HIGH_RISK_FIELD_PATHS = Canonical::UniversalEngine::HIGH_RISK_EVIDENCE_PATHS.freeze
    APPROVED_ROUTES = Canonical::UniversalEngine::APPROVED_ROUTES.freeze
    BENCHMARKED_CAPABILITY_LEVELS = %w[benchmarked pilot_ready production].freeze

    Decision = Data.define(:auto_acceptable, :operator_confirmation_required, :reasons, :hard_blocking_reasons)

    attr_reader :revision

    def initialize(revision)
      @revision = revision
    end

    def decision
      hard_blocking_reasons = []
      hard_blocking_reasons << "missing provenance" if missing_provenance?
      hard_blocking_reasons << "unapproved route" unless route_approved?
      hard_blocking_reasons << "unbenchmarked capability profile" unless capability_benchmarked?
      reasons = hard_blocking_reasons.dup

      blocking_codes = revision.unresolved_blocking_findings.pluck(:code)
      reasons << "unresolved critical/high findings: #{blocking_codes.join(', ')}" if blocking_codes.any?

      missing_evidence = revision.high_risk_changed_paths_without_evidence_or_confirmation
      reasons << "changed high-risk fields lack evidence or explicit confirmation: #{missing_evidence.join(', ')}" if missing_evidence.any?

      Decision.new(
        auto_acceptable: reasons.empty?,
        operator_confirmation_required: blocking_codes.any? || missing_evidence.any?,
        reasons: reasons,
        hard_blocking_reasons: hard_blocking_reasons
      )
    end

    def auto_acceptable?
      decision.auto_acceptable
    end

    def confirmation_required?
      decision.operator_confirmation_required
    end

    private

    def missing_provenance?
      provenance = revision.provenance || {}
      %w[idempotency_key schema_version route profile_version].any? { |key| provenance[key].blank? }
    end

    def route_approved?
      APPROVED_ROUTES.include?(revision.document.route.to_s)
    end

    def capability_benchmarked?
      capability = revision.provenance.fetch("capability", {})
      level = capability["level"] || revision.document.capability_profile
      level.blank? || BENCHMARKED_CAPABILITY_LEVELS.include?(level)
    end
  end
end
