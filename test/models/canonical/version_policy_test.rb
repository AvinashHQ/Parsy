# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class VersionPolicyTest < Minitest::Test
    FIXTURE_PATH = Rails.root.join("test/fixtures/files/canonical/fix_001_minimal_visual_usd.json")
    PROFILE_DIR = Rails.root.join("test/fixtures/files/canonical/region_profiles")

    def test_accepts_current_schema_and_profile_versions
      invoice = Canonical::Invoice.from_json(FIXTURE_PATH.read)

      compatibility = Canonical::VersionPolicy.invoice_compatibility(invoice)

      assert_predicate compatibility, :compatible
      refute_predicate compatibility, :migration_required
      assert_predicate invoice, :compatible_version?
    end

    def test_rejects_unsupported_schema_major_version
      compatibility = Canonical::VersionPolicy.schema_compatibility("3.0")

      refute_predicate compatibility, :compatible
      assert_equal "unsupported schema major version", compatibility.reason
    end

    def test_rejects_future_schema_minor_version
      compatibility = Canonical::VersionPolicy.schema_compatibility("2.1")

      refute_predicate compatibility, :compatible
      assert_equal "future schema minor version", compatibility.reason
    end

    def test_rejects_unknown_profile_id
      attributes = JSON.parse(FIXTURE_PATH.read)
      attributes["locale"]["applied_region_pack"]["id"] = "some_regional_pack_v1"
      invoice = Canonical::Invoice.from_hash(attributes)

      compatibility = Canonical::VersionPolicy.invoice_compatibility(invoice)

      refute_predicate compatibility, :compatible
      assert_equal "profile id is not global_generic_v1", compatibility.reason
    end

    def test_rejects_future_profile_minor_version
      compatibility = Canonical::VersionPolicy.profile_compatibility(
        profile_id: "global_generic_v1",
        profile_version: "1.1.0"
      )

      refute_predicate compatibility, :compatible
      assert_equal "future profile minor version", compatibility.reason
    end

    def test_accepts_current_profile_document_fixture
      profile = JSON.parse(PROFILE_DIR.join("global_generic_v1.json").read)

      compatibility = Canonical::VersionPolicy.profile_document_compatibility(profile)

      assert_predicate compatibility, :compatible
      refute_predicate compatibility, :migration_required
    end

    def test_rejects_future_profile_document_fixture
      profile = JSON.parse(PROFILE_DIR.join("global_generic_v1_future_minor.json").read)

      compatibility = Canonical::VersionPolicy.profile_document_compatibility(profile)

      refute_predicate compatibility, :compatible
      assert_equal "future profile minor version", compatibility.reason
    end

    def test_rejects_unsupported_major_profile_document_fixture
      profile = JSON.parse(PROFILE_DIR.join("global_generic_v1_unsupported_major.json").read)

      compatibility = Canonical::VersionPolicy.profile_document_compatibility(profile)

      refute_predicate compatibility, :compatible
      assert_equal "unsupported profile major version", compatibility.reason
    end
  end
end
