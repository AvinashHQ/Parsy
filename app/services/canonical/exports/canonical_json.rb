# frozen_string_literal: true

require "json"

module Canonical
  module Exports
    class CanonicalJson
      def self.call(invoice:, review_status:)
        raise ArgumentError, "review_status is required" if review_status.to_s.empty?

        JSON.generate(
          {
            "export_version" => "m1.0",
            "schema_version" => invoice.schema_version,
            "review_status" => review_status,
            "canonical_invoice" => invoice.to_h
          }
        )
      end
    end
  end
end
