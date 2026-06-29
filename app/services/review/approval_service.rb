# frozen_string_literal: true

module Review
  class ApprovalService
    ConfirmationRequired = Class.new(StandardError)

    def self.call(revision:, actor:, confirmation: false, reason: nil)
      new(revision:, actor:, confirmation:, reason:).call
    end

    def initialize(revision:, actor:, confirmation:, reason:)
      @revision = revision
      @actor = actor
      @confirmation = ActiveModel::Type::Boolean.new.cast(confirmation)
      @reason = reason
    end

    def call
      ApplicationRecord.transaction do
        policy = AcceptancePolicy.new(revision)
        decision = policy.decision
        raise ConfirmationRequired, decision.hard_blocking_reasons.join("; ") if decision.hard_blocking_reasons.any?
        raise ConfirmationRequired, decision.reasons.join("; ") if !decision.auto_acceptable && !confirmation

        if confirmation
          revision.findings.unresolved.blocking.update_all(resolution_state: "confirmed", updated_at: Time.current)
          revision.changed_field_paths.each do |path|
            next unless AcceptancePolicy::HIGH_RISK_FIELD_PATHS.include?(path)
            next if revision.evidence_for?(path)

            revision.evidence_references.create!(document: revision.document, field_path: path, source_kind: "operator_confirmation", operator_confirmed: true, text_snippet: reason.to_s.first(500))
          end
        end

        revision.update!(status: "approved", approved_by: actor, approved_at: Time.current)
        revision.document.update!(status: "approved", approved_revision: revision, current_revision: revision)
        revision.document.events.create!(
          batch: revision.document.batch,
          candidate_revision: revision,
          actor: actor,
          action: confirmation ? "approved_with_confirmation" : "approved",
          reason: reason,
          metadata: { "policy_reasons" => decision.reasons }
        )
        revision.document.batch.refresh_status!
        revision
      end
    end

    private

    attr_reader :revision, :actor, :confirmation, :reason
  end
end
