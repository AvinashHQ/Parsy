# frozen_string_literal: true

module Review
  class RiskQueue
    def self.call(batch)
      batch.documents.reviewable.risk_ranked.includes(current_revision: [ :findings, :evidence_references ])
    end
  end
end
