# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class MigrationPolicyTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_current_schema_migration_is_noop_with_rollback_snapshot
      attributes = JSON.parse(FIXTURE_DIR.join("fix_013_schema_minor_migration.json").read)
      result = Canonical::MigrationPolicy.new.migrate_invoice(attributes)

      refute_predicate result, :migrated?
      assert_equal "2.0", result.from_schema_version
      assert_equal "2.0", result.to_schema_version
      assert_equal attributes, result.attributes
      assert_equal attributes, Canonical::MigrationPolicy.new.rollback(result)
      refute_empty result.rollback_digest
    end

    def test_compatible_minor_migration_uses_registered_deterministic_migrator
      attributes = JSON.parse(FIXTURE_DIR.join("fix_013_schema_minor_migration.json").read)
      migrator = lambda do |candidate|
        candidate.merge(
          "schema_version" => "2.1",
          "migration_marker" => "fixture-only-deterministic-upgrade"
        )
      end
      policy = Canonical::MigrationPolicy.new(current_schema_version: "2.1", migrators: { [ "2.0", "2.1" ] => migrator })

      result = policy.migrate_invoice(attributes)

      assert_predicate result, :migrated?
      assert_equal "2.0", result.from_schema_version
      assert_equal "2.1", result.to_schema_version
      assert_equal "fixture-only-deterministic-upgrade", result.attributes.fetch("migration_marker")
      assert_equal attributes, policy.rollback(result)
    end

    def test_compatible_minor_without_registered_migrator_is_rejected
      attributes = JSON.parse(FIXTURE_DIR.join("fix_013_schema_minor_migration.json").read)
      policy = Canonical::MigrationPolicy.new(current_schema_version: "2.1")

      error = assert_raises(Canonical::MigrationPolicy::UnsupportedVersion) { policy.migrate_invoice(attributes) }

      assert_match(/no deterministic migrator registered/, error.message)
    end

    def test_unsupported_major_version_is_rejected
      attributes = JSON.parse(FIXTURE_DIR.join("fix_014_unsupported_major_version.json").read)

      error = assert_raises(Canonical::MigrationPolicy::UnsupportedVersion) { Canonical::MigrationPolicy.new.migrate_invoice(attributes) }

      assert_equal "unsupported schema major version", error.message
    end
  end
end
