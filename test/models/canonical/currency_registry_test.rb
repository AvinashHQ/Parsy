# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class CurrencyRegistryTest < Minitest::Test
    def test_known_pilot_currency_minor_units
      assert_equal 2, Canonical::CurrencyRegistry.minor_units("USD")
      assert_equal 2, Canonical::CurrencyRegistry.minor_units("EUR")
      assert_equal 2, Canonical::CurrencyRegistry.minor_units("GBP")
      assert_equal 0, Canonical::CurrencyRegistry.minor_units("JPY")
      assert_equal 3, Canonical::CurrencyRegistry.minor_units("KWD")
    end

    def test_minor_unit_tolerance_uses_decimal_amounts
      assert_equal "0.01", Canonical::CurrencyRegistry.tolerance("USD").to_s
      assert_equal "1", Canonical::CurrencyRegistry.tolerance("JPY").to_s
      assert_equal "0.001", Canonical::CurrencyRegistry.tolerance("KWD").to_s
    end

    def test_unknown_currency_is_not_silently_treated_as_two_decimal
      assert_raises(KeyError) { Canonical::CurrencyRegistry.minor_units("ZZZ") }
    end
  end
end
