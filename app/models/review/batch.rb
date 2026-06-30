# frozen_string_literal: true

module Review
  class Batch < ApplicationRecord
    self.table_name = "review_batches"

    STATUSES = %w[uploaded processing review completed exported purged].freeze

    belongs_to :tenant, optional: true

    broadcasts_refreshes
    after_update_commit :broadcast_to_tenant
    after_create_commit :broadcast_to_tenant

    has_many :documents, class_name: "Review::Document", foreign_key: :review_batch_id, inverse_of: :batch, dependent: :destroy
    has_many :events, class_name: "Review::Event", foreign_key: :review_batch_id, inverse_of: :batch, dependent: :destroy
    has_many :export_artifacts, class_name: "Review::ExportArtifact", foreign_key: :review_batch_id, inverse_of: :batch, dependent: :destroy
    has_many :purge_evidences, class_name: "Retention::PurgeEvidence", foreign_key: :review_batch_id, inverse_of: :batch, dependent: :destroy


    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    def progress
      total = documents.count
      return { total: 0, completed: 0, needs_review: 0, failed: 0, approved: 0, percent: 0 } if total.zero?

      counts = documents.group(:status).count
      completed = counts.values_at("approved", "exported", "rejected", "failed", "quarantined").compact.sum
      {
        total: total,
        completed: completed,
        needs_review: counts.fetch("needs_review", 0) + counts.fetch("ready_for_approval", 0),
        failed: counts.fetch("failed", 0) + counts.fetch("quarantined", 0),
        approved: counts.fetch("approved", 0) + counts.fetch("exported", 0),
        percent: ((completed.to_f / total) * 100).round
      }
    end

    def refresh_status!
      counts = documents.group(:status).count
      next_status = if documents.none?
        "uploaded"
      elsif counts.keys.all? { |status| %w[approved exported rejected failed quarantined].include?(status) }
        counts.key?("exported") ? "exported" : "completed"
      elsif counts.key?("needs_review") || counts.key?("ready_for_approval")
        "review"
      else
        "processing"
      end

      update!(status: next_status)
    end

    private

    def broadcast_to_tenant
      broadcast_refresh_later_to(tenant) if tenant.present?
    end
  end
end
