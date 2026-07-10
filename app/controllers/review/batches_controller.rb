# frozen_string_literal: true

module Review
  class BatchesController < ApplicationController
    def index
      @batches = tenant_batches.order(updated_at: :desc)
    end

    def show
      @batch = tenant_batches.find(params[:id])
      @progress = Review::BatchProgress.call(@batch)
      @documents = Review::RiskQueue.call(@batch)
      @intake_documents = @batch.documents.order(updated_at: :desc).includes(:current_revision)
      @push_destinations = Destination::DatabaseConnection
                             .where(tenant: current_tenant)
                             .joins(:field_mappings)
                             .where(destination_field_mappings: { source_table: "invoices", status: "confirmed" })
                             .order(:label)
      @batch_pushes = Destination::Push.where(review_batch_id: @batch.id)
                                       .order(created_at: :desc).limit(5)
                                       .includes(:database_connection)
    end

    def destroy
      batch = tenant_batches.find(params[:id])
      Retention::PurgeBatch.call(batch:, actor: current_actor)
      redirect_to review_batches_path, notice: "Batch purged"
    end

    private

    def tenant_batches
      Review::Batch.where(tenant: current_tenant)
    end

    def current_actor
      current_user.email
    end
  end
end
