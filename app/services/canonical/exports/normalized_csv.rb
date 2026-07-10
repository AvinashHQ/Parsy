# frozen_string_literal: true

require "csv"

module Canonical
  module Exports
    class NormalizedCsv
      TABLES = %w[Invoices.csv Parties.csv PartyIdentifiers.csv TaxBreakdowns.csv LineItems.csv].freeze

      def self.call(invoices:, review_statuses:)
        new(invoices: invoices, review_statuses: review_statuses).call
      end

      def initialize(invoices:, review_statuses:)
        @invoices = Array(invoices)
        @review_statuses = review_statuses
      end

      def call
        rows = NormalizedRows.call(invoices: invoices, review_statuses: review_statuses)
        {
          "Invoices.csv" => csv(INVOICE_HEADERS, rows.fetch("invoices")),
          "Parties.csv" => csv(PARTY_HEADERS, rows.fetch("parties")),
          "PartyIdentifiers.csv" => csv(IDENTIFIER_HEADERS, rows.fetch("party_identifiers")),
          "TaxBreakdowns.csv" => csv(TAX_HEADERS, rows.fetch("tax_breakdowns")),
          "LineItems.csv" => csv(LINE_HEADERS, rows.fetch("line_items"))
        }
      end

      INVOICE_HEADERS = %w[document_id schema_version document_type source_family source_profile language_tag supplier_country buyer_country supplier_name buyer_name invoice_number issue_date due_date currency line_extension_amount allowance_total_amount charge_total_amount tax_exclusive_amount total_tax_amount tax_inclusive_amount prepaid_amount withholding_total_amount rounding_amount payable_amount region_pack review_status].freeze
      PARTY_HEADERS = %w[party_id document_id role display_name legal_name trading_name address_line_1 city subdivision postal_code country_code].freeze
      IDENTIFIER_HEADERS = %w[party_id document_id role scheme value issuing_country purpose].freeze
      TAX_HEADERS = %w[tax_id document_id line_id tax_type component jurisdiction_code category_code rate taxable_amount tax_amount payable_effect exemption_code exemption_reason reverse_charge source_label].freeze
      LINE_HEADERS = %w[document_id line_id line_no description item_name seller_item_id buyer_item_id quantity unit_code unit_price price_base_quantity line_net_amount line_gross_amount].freeze

      private

      attr_reader :invoices, :review_statuses

      def csv(headers, rows)
        CSV.generate(write_headers: true, headers: headers) do |csv|
          rows.each { |row| csv << headers.map { |header| neutralize(row[header]) } }
        end
      end

      def neutralize(value)
        FormulaNeutralizer.neutralize(value)
      end
    end
  end
end
