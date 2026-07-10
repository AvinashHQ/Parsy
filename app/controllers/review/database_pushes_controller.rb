# frozen_string_literal: true

module Review
  # The explicit ADR-027 gate: pushes are operator actions on approved
  # documents only, never automatic side effects of approval or export.
  class DatabasePushesController < ApplicationController
    def create
      batch = tenant_batches.find(params[:batch_id])
      connection = tenant_connections.find(params[:destination_connection_id])

      unless batch.documents.where.not(approved_revision_id: nil).exists?
        return redirect_to review_batch_path(batch), alert: "No approved documents to push yet"
      end
      unless connection.field_mappings.exists?(source_table: "invoices", status: "confirmed")
        return redirect_to review_batch_path(batch), alert: "Destination #{connection.label} has no confirmed invoices mapping"
      end

      push = Destination::Push.create!(
        tenant: current_tenant, batch: batch, database_connection: connection,
        actor: current_user.email, status: "pending"
      )
      Destination::PushBatchJob.perform_later(push.id)

      redirect_to review_batch_path(batch), notice: "Push to #{connection.label} started"
    end

    def retry
      push = tenant_pushes.find(params[:id])
      failed_ids = push.failed_document_ids
      return redirect_to review_batch_path(push.batch), alert: "Nothing to retry" if failed_ids.empty?

      Destination::PushBatchJob.perform_later(push.id, document_ids: failed_ids.map(&:to_i))
      redirect_to review_batch_path(push.batch), notice: "Retrying #{failed_ids.size} failed documents"
    end

    private

    def tenant_batches
      Review::Batch.where(tenant: current_tenant)
    end

    def tenant_connections
      Destination::DatabaseConnection.where(tenant: current_tenant)
    end

    def tenant_pushes
      Destination::Push.where(tenant: current_tenant, review_batch_id: params[:batch_id])
    end
  end
end
