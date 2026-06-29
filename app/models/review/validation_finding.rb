# frozen_string_literal: true

module Review
  class ValidationFinding < ApplicationRecord
    self.table_name = "validation_findings"

    SEVERITIES = Canonical::Finding::SEVERITIES
    RESOLUTION_STATES = %w[unresolved resolved confirmed dismissed].freeze
    BLOCKING_SEVERITIES = %w[CRITICAL HIGH].freeze

    belongs_to :document, class_name: "Review::Document", foreign_key: :review_document_id, inverse_of: :findings
    belongs_to :candidate_revision, class_name: "Review::CandidateRevision", foreign_key: :candidate_revision_id, inverse_of: :findings

    validates :code, :message, presence: true
    validates :severity, inclusion: { in: SEVERITIES }
    validates :resolution_state, inclusion: { in: RESOLUTION_STATES }

    scope :unresolved, -> { where(resolution_state: "unresolved") }
    scope :blocking, -> { where(severity: BLOCKING_SEVERITIES) }

    def self.from_canonical!(candidate_revision, finding)
      create!(
        document: candidate_revision.document,
        candidate_revision: candidate_revision,
        code: finding.code,
        severity: finding.severity,
        behavior: finding.behavior,
        field_paths: finding.field_paths,
        message: finding.message,
        observed: finding.observed,
        calculated: finding.calculated,
        tolerance: finding.tolerance,
        pack_id: finding.pack_id,
        pack_version: finding.pack_version,
        metadata: finding.metadata
      )
    end

    def blocking?
      BLOCKING_SEVERITIES.include?(severity)
    end
  end
end
