# frozen_string_literal: true

module Retention
  class PurgeBatch
    def self.call(batch:, actor:)
      new(batch:, actor:).call
    end

    def initialize(batch:, actor:)
      @batch = batch
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        counts = purge_objects
        now = Time.current
        batch.documents.find_each { |document| document.update!(status: "purged", purged_at: now) }
        batch.export_artifacts.find_each { |artifact| artifact.update!(status: "purged", purged_at: now) }
        batch.update!(status: "purged", purge_status: "purged", purged_at: now)
        Retention::PurgeEvidence.create!(tenant: batch.tenant, batch:, actor:, status: "purged", object_counts: counts, purged_at: now)
      end
      batch
    rescue StandardError => error
      batch.update!(purge_status: "failed") if batch.persisted?
      raise error
    end

    private

    attr_reader :batch, :actor

    def purge_objects
      counts = { documents: batch.documents.count, exports: batch.export_artifacts.count, source_files: 0, export_files: 0 }
      batch.documents.find_each do |document|
        if document.source_file.attached?
          document.source_file.purge
          counts[:source_files] += 1
        end
      end
      batch.export_artifacts.find_each do |artifact|
        if artifact.file.attached?
          artifact.file.purge
          counts[:export_files] += 1
        end
      end
      counts
    end
  end
end
