# frozen_string_literal: true

module Operations
  class RestoreVerifier
    Result = Data.define(:ok, :checked, :errors)

    def self.call(tenant:)
      new(tenant:).call
    end

    def initialize(tenant:)
      @tenant = tenant
    end

    def call
      errors = []
      batches = tenant.review_batches.includes(:documents, :export_artifacts)
      errors << "no batches restored" if batches.empty?
      batches.find_each do |batch|
        errors << "batch #{batch.id} has no documents" if batch.documents.empty? && batch.status != "purged"
        batch.documents.find_each do |document|
          errors << "document #{document.id} missing current revision" if %w[needs_review ready_for_approval approved exported].include?(document.status) && document.current_revision_id.blank?
          errors << "document #{document.id} approved without approved revision" if %w[approved exported].include?(document.status) && document.approved_revision_id.blank?
        end
        retention_report = Retention::ReconcileObjects.call(batch:)
        errors << "batch #{batch.id} has orphan blobs" if retention_report.orphan_blob_ids.any?
      end

      Result.new(ok: errors.empty?, checked: { tenants: 1, batches: batches.count }, errors: errors)
    end

    private

    attr_reader :tenant
  end
end
