# frozen_string_literal: true

module Canonical
  module Exports
    # Relational decomposition of canonical invoices — the single row source
    # shared by the file exporters (CSV/XLSX) and the external database writer,
    # so every delivery path emits identical values.
    class NormalizedRows
      TABLES = %w[invoices parties party_identifiers tax_breakdowns line_items].freeze

      def self.call(invoices:, review_statuses:)
        new(invoices: invoices, review_statuses: review_statuses).call
      end

      def initialize(invoices:, review_statuses:)
        @invoices = Array(invoices)
        @review_statuses = review_statuses
      end

      def call
        {
          "invoices" => invoice_rows,
          "parties" => party_rows,
          "party_identifiers" => identifier_rows,
          "tax_breakdowns" => tax_rows,
          "line_items" => line_rows
        }
      end

      private

      attr_reader :invoices, :review_statuses

      def invoice_rows
        invoices.map do |invoice|
          {
            "document_id" => invoice.document_id,
            "schema_version" => invoice.schema_version,
            "document_type" => invoice.document_type,
            "source_family" => invoice.source.family,
            "source_profile" => invoice.source.profile,
            "language_tag" => invoice.locale.document_language,
            "supplier_country" => invoice.locale.supplier_country,
            "buyer_country" => invoice.locale.buyer_country,
            "supplier_name" => invoice.supplier&.display_name,
            "buyer_name" => invoice.buyer&.display_name,
            "invoice_number" => invoice.details.number,
            "issue_date" => invoice.details.issue_date,
            "due_date" => invoice.details.due_date,
            "currency" => invoice.currency,
            "line_extension_amount" => invoice.totals.line_extension_amount,
            "allowance_total_amount" => invoice.totals.allowance_total_amount,
            "charge_total_amount" => invoice.totals.charge_total_amount,
            "tax_exclusive_amount" => invoice.totals.tax_exclusive_amount,
            "total_tax_amount" => invoice.totals.total_tax_amount,
            "tax_inclusive_amount" => invoice.totals.tax_inclusive_amount,
            "prepaid_amount" => invoice.totals.prepaid_amount,
            "withholding_total_amount" => invoice.totals.withholding_total_amount,
            "rounding_amount" => invoice.totals.rounding_amount,
            "payable_amount" => invoice.totals.payable_amount,
            "region_pack" => invoice.locale.applied_region_pack_id,
            "review_status" => review_statuses.fetch(invoice.document_id)
          }
        end
      end

      def party_rows
        invoices.flat_map do |invoice|
          parties(invoice).map do |role, party_id, party|
            address = party.address
            {
              "party_id" => party_id,
              "document_id" => invoice.document_id,
              "role" => role,
              "display_name" => party.display_name,
              "legal_name" => party.legal_name,
              "trading_name" => party.trading_name,
              "address_line_1" => address&.lines&.first,
              "city" => address&.city,
              "subdivision" => address&.subdivision,
              "postal_code" => address&.postal_code,
              "country_code" => address&.country_code
            }
          end
        end
      end

      def identifier_rows
        invoices.flat_map do |invoice|
          parties(invoice).flat_map do |role, party_id, party|
            party.identifiers.map do |identifier|
              {
                "party_id" => party_id,
                "document_id" => invoice.document_id,
                "role" => role,
                "scheme" => identifier.scheme,
                "value" => identifier.value_text,
                "issuing_country" => identifier.issuing_country,
                "purpose" => identifier.purpose
              }
            end
          end
        end
      end

      def tax_rows
        invoices.flat_map do |invoice|
          document_rows = invoice.tax_breakdowns.each_with_index.map { |tax, index| tax_row(invoice, tax, "tax_doc_#{index + 1}", nil) }
          line_rows = invoice.line_items.flat_map do |line_item|
            line_item.tax_breakdowns.each_with_index.map { |tax, index| tax_row(invoice, tax, "tax_line_#{line_item.line_no}_#{index + 1}", line_item.line_id) }
          end
          document_rows + line_rows
        end
      end

      def line_rows
        invoices.flat_map do |invoice|
          invoice.line_items.map do |line_item|
            {
              "document_id" => invoice.document_id,
              "line_id" => line_item.line_id,
              "line_no" => line_item.line_no,
              "description" => line_item.description,
              "item_name" => line_item.item_name,
              "seller_item_id" => line_item.seller_item_id,
              "buyer_item_id" => line_item.buyer_item_id,
              "quantity" => line_item.quantity,
              "unit_code" => line_item.unit_code,
              "unit_price" => line_item.unit_price,
              "price_base_quantity" => line_item.price_base_quantity,
              "line_net_amount" => line_item.line_net_amount,
              "line_gross_amount" => line_item.line_gross_amount
            }
          end
        end
      end

      def parties(invoice)
        [ [ "supplier", "party_supplier_1", invoice.supplier ], [ "buyer", "party_buyer_1", invoice.buyer ], [ "payee", "party_payee_1", invoice.payee ] ].select { |_role, _id, party| party }
      end

      def tax_row(invoice, tax, tax_id, line_id)
        {
          "tax_id" => tax_id,
          "document_id" => invoice.document_id,
          "line_id" => line_id,
          "tax_type" => tax.tax_type,
          "component" => tax.component,
          "jurisdiction_code" => tax.jurisdiction_code,
          "category_code" => tax.category_code,
          "rate" => tax.rate,
          "taxable_amount" => tax.taxable_amount,
          "tax_amount" => tax.tax_amount,
          "payable_effect" => tax.payable_effect,
          "exemption_code" => tax.exemption_code,
          "exemption_reason" => tax.exemption_reason,
          "reverse_charge" => tax.reverse_charge,
          "source_label" => tax.source_label
        }
      end
    end
  end
end
