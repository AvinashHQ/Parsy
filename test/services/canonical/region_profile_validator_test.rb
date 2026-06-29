# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class RegionProfileValidatorTest < Minitest::Test
    PROFILE_DIR = Rails.root.join("test/fixtures/files/canonical/region_profiles")

    def test_accepts_configured_region_profiles_against_profile_schema
      validator = Canonical::RegionProfileValidator.new

      errors_by_profile = validator.validate_configured_profiles

      assert_includes errors_by_profile.keys, "global_generic_v1"
      assert errors_by_profile.values.all?(&:empty?), -> { errors_by_profile.inspect }
    end

    def test_accepts_current_global_profile_fixture
      validator = Canonical::RegionProfileValidator.new
      profile = JSON.parse(PROFILE_DIR.join("global_generic_v1.json").read)

      assert_empty validator.validate(profile)
    end

    def test_accepts_migration_policy_profile_fixtures_as_schema_valid_documents
      validator = Canonical::RegionProfileValidator.new

      %w[
        global_generic_v1_future_minor.json
        global_generic_v1_unsupported_major.json
      ].each do |filename|
        profile = JSON.parse(PROFILE_DIR.join(filename).read)

        assert_empty validator.validate(profile), "expected #{filename} to stay schema-valid for policy testing"
      end
    end

    def test_rejects_country_specific_core_fields_in_profile_documents
      validator = Canonical::RegionProfileValidator.new
      profile = JSON.parse(PROFILE_DIR.join("global_generic_v1.json").read)
      profile["gstin_required"] = true

      errors = validator.validate(profile)

      refute_empty errors
      assert errors.any? do |error|
        error.data_pointer == "/gstin_required" &&
          error.schema_pointer == "/additionalProperties" &&
          error.message.include?("disallowed additional property")
      end
    end
  end
end
