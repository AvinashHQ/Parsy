# frozen_string_literal: true

require "caxlsx"
require "csv"

module Canonical
  module Exports
    class Workbook
      SHEET_NAMES = {
        "Invoices.csv" => "Invoices",
        "Parties.csv" => "Parties",
        "PartyIdentifiers.csv" => "PartyIdentifiers",
        "TaxBreakdowns.csv" => "TaxBreakdowns",
        "LineItems.csv" => "LineItems"
      }.freeze

      def self.call(invoices:, review_statuses:)
        bundle = NormalizedCsv.call(invoices: invoices, review_statuses: review_statuses)
        package = Axlsx::Package.new
        workbook = package.workbook

        bundle.each do |filename, content|
          workbook.add_worksheet(name: SHEET_NAMES.fetch(filename)) do |sheet|
            CSV.parse(content).each { |row| sheet.add_row(row) }
          end
        end

        package.to_stream.read
      end
    end
  end
end
