# frozen_string_literal: true

module Review
  class ApprovedRevisionExporter
    def self.call(batch:, format:, actor: "system")
      new(batch:, format:, actor:).call
    end

    def initialize(batch:, format:, actor:)
      @batch = batch
      @format = format.to_s
      @actor = actor
    end

    def call
      revisions = batch.documents.order(:id).map(&:approved_revision)
      raise Canonical::Exports::ExportService::UnapprovedRevision, "all documents must have approved revisions" if revisions.any?(&:nil?)

      snapshots = revisions.map do |revision|
        Canonical::Exports::RevisionSnapshot.new(revision_id: revision.id, invoice: revision.invoice, review_status: revision.status)
      end
      payload = Canonical::Exports::ExportService.call(revisions: snapshots, format: format)
      bytes = payload.respond_to?(:bytesize) ? payload.bytesize : payload.to_s.bytesize

      artifact = batch.export_artifacts.create!(
        format: format,
        status: "created",
        approved_revision_ids: revisions.map(&:id),
        byte_size: bytes,
        metadata: { "document_count" => revisions.size }
      )

      batch.documents.where(id: revisions.map(&:review_document_id)).update_all(status: "exported", updated_at: Time.current)
      if (document = batch.documents.first)
        batch.events.create!(document: document, candidate_revision: revisions.first, actor: actor, action: "export_created", metadata: { "format" => format, "artifact_id" => artifact.id })
      end
      batch.refresh_status!

      [ artifact, payload ]
    end

    private

    attr_reader :batch, :format, :actor
  end
end
