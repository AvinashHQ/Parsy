# frozen_string_literal: true

module Canonical
  class Invoice
    SCHEMA_VERSION = "2.0"

    attr_reader :attributes

    def self.from_json(payload)
      from_hash(JSON.parse(payload))
    end

    def self.from_hash(attributes)
      new(attributes.deep_stringify_keys)
    end

    def initialize(attributes)
      @attributes = attributes.freeze
    end

    def schema_version
      attributes["schema_version"]
    end

    def document_id
      attributes["document_id"]
    end

    def document_type
      attributes["document_type"]
    end

    def currency
      attributes.dig("invoice", "currency")
    end

    def payable_amount
      attributes.dig("totals", "payable_amount")
    end

    def to_h
      attributes.deep_dup
    end
  end
end
