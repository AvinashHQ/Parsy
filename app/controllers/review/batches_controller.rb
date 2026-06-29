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
