# frozen_string_literal: true

module Review
  class Document < ApplicationRecord
    self.table_name = "review_documents"

    STATUSES = %w[uploaded inspecting routed_structured routed_visual extracting validating needs_review ready_for_approval approved rejected exported failed quarantined purged].freeze
    RISK_WEIGHTS = { "CRITICAL" => 100, "HIGH" => 50, "MEDIUM" => 20, "LOW" => 5, "INFO" => 1 }.freeze

    belongs_to :batch, class_name: "Review::Batch", foreign_key: :review_batch_id, inverse_of: :documents
    belongs_to :current_revision, class_name: "Review::CandidateRevision", optional: true
    belongs_to :approved_revision, class_name: "Review::CandidateRevision", optional: true
    has_many :candidate_revisions, class_name: "Review::CandidateRevision", foreign_key: :review_document_id, inverse_of: :document, dependent: :destroy
    has_many :findings, class_name: "Review::ValidationFinding", foreign_key: :review_document_id, inverse_of: :document, dependent: :destroy
    has_many :evidence_references, class_name: "Review::EvidenceReference", foreign_key: :review_document_id, inverse_of: :document, dependent: :destroy
    has_many :events, class_name: "Review::Event", foreign_key: :review_document_id, inverse_of: :document, dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates :source_sha256, presence: true, uniqueness: { scope: :review_batch_id }
    validates :risk_score, numericality: { greater_than_or_equal_to: 0 }

    scope :reviewable, -> { where(status: %w[needs_review ready_for_approval]) }
    scope :risk_ranked, -> { order(risk_score: :desc, updated_at: :asc) }

    def recompute_risk!
      score = findings.unresolved.sum { |finding| RISK_WEIGHTS.fetch(finding.severity, 0) }
      update!(risk_score: score)
    end

    def next_revision_number
      candidate_revisions.maximum(:revision_number).to_i + 1
    end

    def mark_review_state!
      next_status = current_revision&.approval_ready? ? "ready_for_approval" : "needs_review"
      update!(status: next_status)
      batch.refresh_status!
    end
  end
end
