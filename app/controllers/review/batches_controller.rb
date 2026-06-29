# frozen_string_literal: true

module Review
  class BatchesController < ApplicationController
    def index
      @batches = Review::Batch.order(updated_at: :desc)
    end

    def show
      @batch = Review::Batch.find(params[:id])
      @progress = Review::BatchProgress.call(@batch)
      @documents = Review::RiskQueue.call(@batch)
    end
  end
end
