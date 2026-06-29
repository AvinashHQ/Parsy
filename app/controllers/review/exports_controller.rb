# frozen_string_literal: true

module Review
  class ExportsController < ApplicationController
    def create
      batch = Review::Batch.where(tenant: current_tenant).find(params[:batch_id])
      artifact, _payload = Review::ApprovedRevisionExporter.call(batch: batch, format: params[:format_type] || params[:format] || "json", actor: current_actor)
      redirect_to review_batch_export_download_path(batch, artifact), notice: "Export created"
    end

    private

    def current_actor
      current_user.email
    end
  end
end
