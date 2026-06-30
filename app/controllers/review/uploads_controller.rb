# frozen_string_literal: true

module Review
  class UploadsController < ApplicationController
    def new
    end

    def create
      upload_params = params.fetch(:upload, {})
      result = Intake::OperatorUpload.call(
        tenant: current_tenant,
        actor: current_user.email,
        upload: upload_params[:file],
        batch_name: upload_params[:name]
      )

      if result.batch.present?
        redirect_to review_batch_path(result.batch), notice: result.flash_message
      else
        redirect_to new_review_upload_path, alert: result.flash_message
      end
    rescue Intake::OperatorUpload::InvalidUpload => error
      redirect_to new_review_upload_path, alert: error.message
    end
  end
end
