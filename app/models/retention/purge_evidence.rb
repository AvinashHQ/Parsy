# frozen_string_literal: true

module Retention
  class PurgeEvidence < ApplicationRecord
    self.table_name = "purge_evidences"

    belongs_to :tenant, optional: true
    belongs_to :batch, class_name: "Review::Batch", foreign_key: :review_batch_id

    validates :actor, :status, :purged_at, presence: true
  end
end
