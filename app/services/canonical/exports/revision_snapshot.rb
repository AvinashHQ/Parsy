# frozen_string_literal: true

module Canonical
  module Exports
    class RevisionSnapshot
      APPROVED_STATUSES = %w[APPROVED approved].freeze

      attr_reader :revision_id, :invoice, :review_status

      def initialize(revision_id:, invoice:, review_status:)
        @revision_id = revision_id
        @invoice = invoice
        @review_status = review_status
      end

      def approved?
        APPROVED_STATUSES.include?(review_status.to_s)
      end
    end
  end
end
