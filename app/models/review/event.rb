# frozen_string_literal: true

module Review
  class Event < ApplicationRecord
    self.table_name = "review_events"

    belongs_to :batch, class_name: "Review::Batch", foreign_key: :review_batch_id, inverse_of: :events
    belongs_to :document, class_name: "Review::Document", foreign_key: :review_document_id, inverse_of: :events
    belongs_to :candidate_revision, class_name: "Review::CandidateRevision", foreign_key: :candidate_revision_id, inverse_of: :events, optional: true

    validates :actor, :action, presence: true
  end
end
