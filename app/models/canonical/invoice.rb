# frozen_string_literal: true

module Canonical
  class Invoice < ValueObject
    SCHEMA_VERSION = VersionPolicy::CURRENT_SCHEMA_VERSION

    def self.from_json(payload)
      from_hash(JSON.parse(payload))
    end

    def schema_version
      value(:schema_version)
    end

    def document_id
      value(:document_id)
    end

    def document_type
      value(:document_type)
    end

    def source
      object(:source, Source)
    end

    def locale
      object(:locale, Locale)
    end

    def supplier
      object(:supplier, Party)
    end

    def buyer
      object(:buyer, Party)
    end

    def payee
      object(:payee, Party)
    end

    def details
      object(:invoice, InvoiceDetails)
    end

    def references
      objects(:references, Reference)
    end

    def allowances_charges
      objects(:allowances_charges, AllowanceCharge)
    end

    def totals
      object(:totals, Totals)
    end

    def tax_breakdowns
      objects(:tax_breakdowns, TaxBreakdown)
    end

    def line_items
      objects(:line_items, LineItem)
    end

    def payment
      object(:payment, Payment)
    end

    def evidence
      objects(:evidence, Evidence)
    end

    def uncertainties
      objects(:uncertainties, Uncertainty)
    end

    def currency
      details&.currency
    end

    def payable_amount
      totals&.payable_amount
    end

    def compatible_version?
      VersionPolicy.compatible_invoice?(self)
    end
  end
end
