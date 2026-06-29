# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class SchemaValidatorTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_accepts_m1_contract_foundation_fixtures
      validator = Canonical::SchemaValidator.new

      %w[
        fix_001_minimal_visual_usd.json
        fix_002_credit_note_gbp.json
        fix_003_zero_minor_unit_jpy.json
        fix_005_generic_vat_eur.json
      ].each do |filename|
        attributes = JSON.parse(FIXTURE_DIR.join(filename).read)

        assert_empty validator.validate(attributes), "expected #{filename} to match canonical invoice v2 schema"
      end
    end

    def test_reports_schema_errors_without_logging_invoice_content
      validator = Canonical::SchemaValidator.new
      attributes = JSON.parse(FIXTURE_DIR.join("fix_001_minimal_visual_usd.json").read)
      attributes.delete("document_type")

      errors = validator.validate(attributes)

      refute_empty errors
      assert errors.any? { |error| error.data_pointer == "" && error.type == "required" }
      assert errors.none? { |error| error.message.include?("Northstar") }
    end

    def test_rejects_accidental_binary_numeric_money_values
      validator = Canonical::SchemaValidator.new
      attributes = JSON.parse(FIXTURE_DIR.join("fix_001_minimal_visual_usd.json").read)
      attributes["totals"]["payable_amount"] = 100.00

      errors = validator.validate(attributes)

      assert errors.any? { |error| error.data_pointer == "/totals/payable_amount" }
    end
  end
end
