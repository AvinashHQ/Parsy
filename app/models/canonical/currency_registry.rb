# frozen_string_literal: true

module Canonical
  class CurrencyRegistry
    MINOR_UNITS = {
      "BHD" => 3,
      "EUR" => 2,
      "GBP" => 2,
      "INR" => 2,
      "IQD" => 3,
      "JOD" => 3,
      "JPY" => 0,
      "KWD" => 3,
      "LYD" => 3,
      "OMR" => 3,
      "TND" => 3,
      "USD" => 2
    }.freeze

    def self.minor_units(currency)
      normalized = normalize_currency(currency)
      MINOR_UNITS.fetch(normalized) { raise KeyError, "unknown ISO currency #{normalized}" }
    end

    def self.known?(currency)
      MINOR_UNITS.key?(normalize_currency(currency))
    end

    def self.tolerance(currency)
      minor_units = minor_units(currency)
      DecimalAmount.parse(minor_units.zero? ? "1" : "0.#{'0' * (minor_units - 1)}1")
    end

    def self.normalize_currency(currency)
      currency.to_s.upcase
    end
    private_class_method :normalize_currency
  end
end
