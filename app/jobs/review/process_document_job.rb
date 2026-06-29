# frozen_string_literal: true

module Review
  class ProcessDocumentJob < ApplicationJob
    queue_as :review

    def perform(document_id)
      document = Review::Document.find(document_id)
      return if document.approved_revision_id.present? || document.status == "exported"

      document.update!(status: "validating")
      if document.current_revision.present?
        document.recompute_risk!
        document.mark_review_state!
        document.events.create!(batch: document.batch, candidate_revision: document.current_revision, actor: "system", action: "review_state_refreshed")
      else
        document.update!(status: "needs_review")
        document.events.create!(batch: document.batch, actor: "system", action: "review_waiting_for_candidate")
      end
    end
  end
end
