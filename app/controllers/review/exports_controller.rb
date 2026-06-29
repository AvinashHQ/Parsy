# frozen_string_literal: true

module Review
  class ExportsController < ApplicationController
    def create
      batch = Review::Batch.find(params[:batch_id])
      artifact, payload = Review::ApprovedRevisionExporter.call(batch: batch, format: params[:format_type] || params[:format] || "json", actor: current_actor)
      send_data payload, filename: "batch-#{batch.id}-export.#{artifact.format}", type: mime_type(artifact.format)
    end

    private

    def current_actor
      request.headers["X-Operator"] || "operator"
    end

    def mime_type(format)
      case format
      when "json" then "application/json"
      when "csv" then "application/zip"
      when "xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      else "application/octet-stream"
      end
    end
  end
end
