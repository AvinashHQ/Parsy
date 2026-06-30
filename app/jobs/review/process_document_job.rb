# frozen_string_literal: true

module Review
  class ProcessDocumentJob < ApplicationJob
    queue_as :review

    def perform(document_id, force: false)
      document = Review::Document.find(document_id)
      return if document.approved_revision_id.present? || document.status == "exported"

      if document.current_revision.present? && !force
        document.recompute_risk!
        document.mark_review_state!
        document.events.create!(batch: document.batch, candidate_revision: document.current_revision, actor: "system", action: "review_state_refreshed")
      else
        Extraction::DocumentExtractor.call(document: document)
      end
    end
  end
end
