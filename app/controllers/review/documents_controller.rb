# frozen_string_literal: true

module Review
  class DocumentsController < ApplicationController
    rescue_from Review::ApprovalService::ConfirmationRequired, with: :confirmation_required

    def show
      @document = tenant_documents.find(params[:id])
      @revision = @document.current_revision
      @decision = @revision ? Review::AcceptancePolicy.new(@revision).decision : nil
      @next_document = next_document
    end

    def update
      document = tenant_documents.find(params[:id])
      Review::RevisionEditor.call(
        revision: document.current_revision,
        patch: canonical_patch,
        overrides: override_params,
        actor: current_actor,
        reason: params[:reason].presence || "operator edit"
      )
      redirect_to review_document_path(document), notice: "Saved revision"
    end

    def approve
      document = tenant_documents.find(params[:id])
      Review::ApprovalService.call(
        revision: document.current_revision,
        actor: current_actor,
        confirmation: params[:confirm_blocking_findings],
        reason: params[:reason]
      )
      redirect_to next_review_path(document), notice: "Approved document"
    end

    def reject
      document = tenant_documents.find(params[:id])
      document.current_revision&.update!(status: "rejected")
      document.update!(status: "rejected")
      document.events.create!(batch: document.batch, candidate_revision: document.current_revision, actor: current_actor, action: "rejected", reason: params[:reason])
      document.batch.refresh_status!
      redirect_to review_batch_path(document.batch), notice: "Rejected document"
    end

    private

    def tenant_documents
      Review::Document.joins(:batch).where(review_batches: { tenant_id: current_tenant.id })
    end

    def canonical_patch
      params.fetch(:canonical_invoice, {}).permit(supplier: [ :display_name ], invoice: [ :number, :currency ], totals: [ :payable_amount ]).to_h
    end

    def override_params
      params.fetch(:overrides, {}).permit(:document_language, :supplier_country, :buyer_country, :currency, :source_format_family, :source_format_profile, :rule_pack_id, :rule_pack_version).to_h
    end

    def current_actor
      current_user.email
    end

    def next_document
      return nil unless @document&.batch

      Review::RiskQueue.call(@document.batch).where.not(id: @document.id).first
    end

    def next_review_path(document)
      if (target = Review::RiskQueue.call(document.batch).where.not(id: document.id).first)
        review_document_path(target)
      else
        review_batch_path(document.batch)
      end
    end

    def confirmation_required(error)
      redirect_to review_document_path(params[:id]), alert: "Confirmation required: #{error.message}"
    end
  end
end
