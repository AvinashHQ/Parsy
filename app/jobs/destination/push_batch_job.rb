# frozen_string_literal: true

module Destination
  # Runs one approval-gated database push out-of-band. Only documents with an
  # approved revision are ever written (ADR-027); a document_ids subset re-runs
  # just those documents (retry) and merges into the same push record — safe
  # because the writer is idempotent.
  class PushBatchJob < ApplicationJob
    queue_as :destination

    def perform(push_id, document_ids: nil)
      push = Destination::Push.find(push_id)
      return if push.status == "running"

      push.update!(status: "running", started_at: push.started_at || Time.current, failure_reason: nil)

      documents = push.batch.documents.where.not(approved_revision_id: nil).order(:id)
      documents = documents.where(id: document_ids) if document_ids
      documents = documents.includes(:approved_revision).to_a

      result = InvoiceWriter.call(
        revisions: documents.map(&:approved_revision),
        connection: push.database_connection
      )

      record_results(push, documents, result)
      push.refresh_counts_and_status!
      record_event(push)
    rescue InvoiceWriter::NoConfirmedMapping, Adapters::Error => error
      push.update!(status: "failed", failure_reason: error.message, finished_at: Time.current)
      record_event(push)
    end

    private

    def record_results(push, documents, result)
      documents.zip(result.results).each do |document, document_result|
        push.document_results[document.id.to_s] = {
          "status" => document_result.status,
          "operation" => document_result.operation,
          "issues" => document_result.issues,
          "canonical_document_id" => document_result.document_id
        }
      end
    end

    # Content-free provenance: counts, codes, actor, destination id — never
    # invoice values (M4-04 logging posture).
    def record_event(push)
      document = push.batch.documents.first
      return unless document

      push.batch.events.create!(
        document: document,
        actor: push.actor,
        action: "database_push_completed",
        metadata: {
          "push_id" => push.id,
          "destination_connection_id" => push.database_connection_id,
          "status" => push.status,
          "pushed_count" => push.pushed_count,
          "failed_count" => push.failed_count,
          "failure_reason" => push.failure_reason
        }.compact
      )
    end
  end
end
