# frozen_string_literal: true

module Retention
  class ReconcileObjects
    Report = Data.define(:batch_id, :expected_source_files, :attached_source_files, :expected_export_files, :attached_export_files, :orphan_blob_ids) do
      def clean?
        expected_source_files == attached_source_files && expected_export_files == attached_export_files && orphan_blob_ids.empty?
      end
    end

    def self.call(batch:)
      new(batch:).call
    end

    def initialize(batch:)
      @batch = batch
    end

    def call
      purged = batch.purge_status == "purged" || batch.status == "purged"
      expected_source = purged ? 0 : batch.documents.count
      attached_source = batch.documents.count { |document| document.source_file.attached? }
      expected_exports = purged ? 0 : batch.export_artifacts.count
      attached_exports = batch.export_artifacts.count { |artifact| artifact.file.attached? }
      attached_blob_ids = ActiveStorage::Attachment.where(record: batch.documents.to_a + batch.export_artifacts.to_a).pluck(:blob_id)
      orphan_blob_ids = ActiveStorage::Blob.where.not(id: ActiveStorage::Attachment.select(:blob_id)).pluck(:id)

      Report.new(batch_id: batch.id, expected_source_files: expected_source, attached_source_files: attached_source, expected_export_files: expected_exports, attached_export_files: attached_exports, orphan_blob_ids: orphan_blob_ids - attached_blob_ids)
    end

    private

    attr_reader :batch
  end
end
