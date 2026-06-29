# frozen_string_literal: true

module Canonical
  module Exports
    class ExportService
      UnsupportedFormat = Class.new(StandardError)
      UnapprovedRevision = Class.new(StandardError)

      def self.call(revisions:, format:)
        new(revisions: revisions, format: format).call
      end

      def initialize(revisions:, format:)
        @revisions = Array(revisions)
        @format = format.to_sym
      end

      def call
        unapproved = revisions.reject(&:approved?)
        raise UnapprovedRevision, "unapproved revisions cannot be exported: #{unapproved.map(&:revision_id).join(', ')}" if unapproved.any?

        invoices = revisions.map(&:invoice)
        statuses = revisions.to_h { |revision| [ revision.invoice.document_id, revision.review_status ] }

        case format
        when :json
          CanonicalJson.call(invoice: invoices.fetch(0), review_status: revisions.fetch(0).review_status)
        when :csv
          NormalizedCsv.call(invoices: invoices, review_statuses: statuses)
        when :xlsx
          Workbook.call(invoices: invoices, review_statuses: statuses)
        else
          raise UnsupportedFormat, "unsupported export format #{format}"
        end
      end

      private

      attr_reader :revisions, :format
    end
  end
end
