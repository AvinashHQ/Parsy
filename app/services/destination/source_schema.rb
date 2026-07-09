# frozen_string_literal: true

module Destination
  # Single source of truth for the canonical relational form the DB delivery
  # maps FROM: the Canonical::Exports::NormalizedCsv decomposition Parsy
  # already exports. MVP scope is invoices + line_items (M4.5-08); the
  # structure is table-generic so the remaining decomposition tables can be
  # added without rework. A test pins these column lists to the NormalizedCsv
  # headers so the two can never drift apart.
  module SourceSchema
    COLUMN_KINDS = {
      "invoices" => {
        "document_id" => :text, "schema_version" => :text, "document_type" => :text,
        "source_family" => :text, "source_profile" => :text, "language_tag" => :text,
        "supplier_country" => :text, "buyer_country" => :text, "supplier_name" => :text,
        "buyer_name" => :text, "invoice_number" => :text, "issue_date" => :date,
        "due_date" => :date, "currency" => :text,
        "line_extension_amount" => :decimal, "allowance_total_amount" => :decimal,
        "charge_total_amount" => :decimal, "tax_exclusive_amount" => :decimal,
        "total_tax_amount" => :decimal, "tax_inclusive_amount" => :decimal,
        "prepaid_amount" => :decimal, "withholding_total_amount" => :decimal,
        "rounding_amount" => :decimal, "payable_amount" => :decimal,
        "region_pack" => :text, "review_status" => :text
      }.freeze,
      "line_items" => {
        "document_id" => :text, "line_id" => :text, "line_no" => :integer,
        "description" => :text, "item_name" => :text, "seller_item_id" => :text,
        "buyer_item_id" => :text, "quantity" => :decimal, "unit_code" => :text,
        "unit_price" => :decimal, "price_base_quantity" => :decimal,
        "line_net_amount" => :decimal, "line_gross_amount" => :decimal
      }.freeze
    }.freeze

    # Stable keys the idempotent writer upserts on; a mapping cannot be
    # confirmed while these are unmapped.
    REQUIRED_COLUMNS = {
      "invoices" => %w[document_id].freeze,
      "line_items" => %w[document_id line_id].freeze
    }.freeze

    def self.tables
      COLUMN_KINDS.keys
    end

    def self.table?(name)
      COLUMN_KINDS.key?(name)
    end

    def self.column_names(table)
      COLUMN_KINDS.fetch(table).keys
    end

    def self.column?(table, column)
      COLUMN_KINDS.fetch(table).key?(column)
    end

    def self.kind(table, column)
      COLUMN_KINDS.fetch(table)[column]
    end

    def self.required_columns(table)
      REQUIRED_COLUMNS.fetch(table)
    end
  end
end
