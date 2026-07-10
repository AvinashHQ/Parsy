# frozen_string_literal: true

module Destination
  # Provenance record for one approval-gated "Push to database" action:
  # who pushed which batch into which destination, when, and how every
  # document fared. Results hold counts and content-free codes only.
  class Push < ApplicationRecord
    self.table_name = "destination_pushes"

    STATUSES = %w[pending running pushed partial failed].freeze
    TERMINAL_STATUSES = %w[pushed partial failed].freeze

    belongs_to :tenant
    belongs_to :batch, class_name: "Review::Batch", foreign_key: :review_batch_id, inverse_of: false
    belongs_to :database_connection, class_name: "Destination::DatabaseConnection"

    validates :actor, presence: true
    validates :status, inclusion: { in: STATUSES }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def failed_document_ids
      document_results.select { |_id, result| result["status"] == "failed" }.keys
    end

    def refresh_counts_and_status!
      statuses = document_results.values.map { |result| result["status"] }
      self.pushed_count = statuses.count("pushed")
      self.failed_count = statuses.count("failed")
      self.status = if statuses.empty? || statuses.none?("pushed")
        "failed"
      elsif statuses.all?("pushed")
        "pushed"
      else
        "partial"
      end
      self.finished_at = Time.current
      save!
    end
  end
end
