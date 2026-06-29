# frozen_string_literal: true

require "digest"
require "json"

module Canonical
  class DuplicateFingerprint
    Result = Data.define(:tenant_id, :fingerprint, :parts, :complete) do
      def complete? = complete
    end

    def self.call(invoice:, tenant_id:)
      new(invoice: invoice, tenant_id: tenant_id).call
    end

    def initialize(invoice:, tenant_id:)
      @invoice = invoice
      @tenant_id = tenant_id.to_s
    end

    def call
      parts = {
        tenant_id: tenant_id,
        supplier_key: supplier_key,
        invoice_number_key: normalize_key(invoice.details.number),
        issue_date: invoice.details.issue_date,
        currency: invoice.currency&.upcase,
        payable_minor_units: payable_minor_units,
        buyer_key: buyer_key,
        source_hash: source_hash
      }
      material = JSON.generate(parts.sort.to_h)
      Result.new(tenant_id: tenant_id, fingerprint: Digest::SHA256.hexdigest(material), parts: parts, complete: required_parts_present?(parts))
    end

    private

    attr_reader :invoice, :tenant_id

    def supplier_key
      party_key(invoice.supplier)
    end

    def buyer_key
      party_key(invoice.buyer)
    end

    def party_key(party)
      return nil unless party

      identifier = party.identifiers.first
      return identifier_key(identifier) if identifier

      [ normalize_key(party.display_name), address_key(party.address) ].compact.join(":")
    end

    def identifier_key(identifier)
      [ identifier.scheme, identifier.issuing_country, identifier.value_text ].map { |value| normalize_key(value) }.join(":")
    end

    def address_key(address)
      return nil unless address

      [ address.lines&.join(" "), address.city, address.postal_code, address.normalized_country_code ].map { |value| normalize_key(value) }.reject(&:empty?).join(":")
    end

    def payable_minor_units
      return nil if invoice.currency.nil? || invoice.payable_amount.nil? || !CurrencyRegistry.known?(invoice.currency)

      DecimalAmount.parse(invoice.payable_amount).to_minor_units(invoice.currency).to_s
    rescue ArgumentError
      nil
    end

    def source_hash
      invoice.source["file_hash"]
    end

    def required_parts_present?(parts)
      parts.values_at(:tenant_id, :supplier_key, :invoice_number_key, :issue_date, :currency, :payable_minor_units).all?(&:present?)
    end

    def normalize_key(value)
      value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
