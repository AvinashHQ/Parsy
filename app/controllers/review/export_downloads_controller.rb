# frozen_string_literal: true

module Review
  class ExportDownloadsController < ApplicationController
    def show
      batch = Review::Batch.where(tenant: current_tenant).find(params[:batch_id])
      artifact = batch.export_artifacts.find(params[:id])
      raise ActiveRecord::RecordNotFound unless artifact.file.attached?

      expires_in 5.minutes, private: true
      send_data artifact.file.download, filename: artifact.file.filename.to_s, type: artifact.file.content_type, disposition: "attachment"
    end
  end
end
