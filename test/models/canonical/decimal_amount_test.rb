# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class DecimalAmountTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_parses_and_normalizes_decimal_strings_without_forcing_places
      assert_equal "100", Canonical::DecimalAmount.parse("100.00").to_s
      assert_equal "10.125", Canonical::DecimalAmount.parse("10.125").to_s
      assert_equal "0", Canonical::DecimalAmount.parse("-0.00").to_s
    end

    def test_rejects_binary_numeric_inputs
      assert_raises(ArgumentError) { Canonical::DecimalAmount.parse(0.1) }
      assert_raises(ArgumentError) { Canonical::DecimalAmount.parse(1) }
    end

    def test_accepts_at_most_eight_fractional_digits
      assert_equal "1.12345678", Canonical::DecimalAmount.parse("1.12345678").to_s

      assert_raises(ArgumentError) { Canonical::DecimalAmount.parse("1.123456789") }
    end

    def test_decimal_arithmetic_is_exact
      result = Canonical::DecimalAmount.parse("0.10") + Canonical::DecimalAmount.parse("0.20")

      assert_equal Canonical::DecimalAmount.parse("0.30"), result
      assert_equal "0.3", result.to_s
    end

    def test_converts_to_minor_units_for_two_zero_and_three_unit_currencies
      assert_equal 10_000, Canonical::DecimalAmount.parse("100.00").to_minor_units("USD")
      assert_equal 10_000, Canonical::DecimalAmount.parse("10000").to_minor_units("JPY")
      assert_equal 10_125, Canonical::DecimalAmount.parse("10.125").to_minor_units("KWD")
    end

    def test_allows_trailing_zero_fraction_for_zero_minor_currency
      amount = Canonical::DecimalAmount.parse("10000.00")

      assert amount.fits_minor_units?("JPY")
      assert_equal 10_000, amount.to_minor_units("JPY")
      assert_equal "10000", amount.to_s
    end

    def test_rejects_non_zero_fraction_beyond_currency_minor_units
      refute Canonical::DecimalAmount.parse("100.001").fits_minor_units?("USD")
      refute Canonical::DecimalAmount.parse("10000.50").fits_minor_units?("JPY")

      assert_raises(ArgumentError) { Canonical::DecimalAmount.parse("10000.50").to_minor_units("JPY") }
    end
    def test_fixture_payable_amounts_match_currency_precision
      {
        "fix_001_minimal_visual_usd.json" => 10_000,
        "fix_003_zero_minor_unit_jpy.json" => 10_000,
        "fix_004_three_minor_unit_kwd.json" => 10_125
      }.each do |filename, expected_minor_units|
        invoice = Canonical::Invoice.from_json(FIXTURE_DIR.join(filename).read)
        payable = Canonical::DecimalAmount.parse(invoice.payable_amount)

        assert payable.fits_minor_units?(invoice.currency), filename
        assert_equal expected_minor_units, payable.to_minor_units(invoice.currency), filename
      end
    end
  end
end
