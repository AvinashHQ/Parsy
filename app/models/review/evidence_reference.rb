# frozen_string_literal: true

module Review
  class EvidenceReference < ApplicationRecord
    self.table_name = "evidence_references"

    belongs_to :document, class_name: "Review::Document", foreign_key: :review_document_id, inverse_of: :evidence_references
    belongs_to :candidate_revision, class_name: "Review::CandidateRevision", foreign_key: :candidate_revision_id, inverse_of: :evidence_references

    validates :field_path, :source_kind, presence: true
    validates :text_snippet, length: { maximum: 500 }, allow_nil: true

    def self.from_canonical!(candidate_revision, evidence)
      create!(
        document: candidate_revision.document,
        candidate_revision: candidate_revision,
        field_path: evidence.field_path,
        source_kind: evidence.source_kind,
        page: evidence.page,
        source_path: evidence.source_path,
        text_snippet: evidence.text,
        bbox: evidence.bbox || {}
      )
    end
  end
end
