# frozen_string_literal: true

require "digest"

module Canonical
  class MigrationPolicy
    UnsupportedVersion = Class.new(StandardError)

    Result = Data.define(:attributes, :migrated, :from_schema_version, :to_schema_version, :rollback_attributes, :rollback_digest) do
      def migrated? = migrated
    end

    def initialize(current_schema_version: VersionPolicy::CURRENT_SCHEMA_VERSION, migrators: {})
      @current_schema_version = current_schema_version
      @migrators = migrators
    end

    def migrate_invoice(attributes)
      original = attributes.deep_stringify_keys
      from_version = original.fetch("schema_version")
      compatibility = VersionPolicy.schema_compatibility(from_version, current_schema_version: current_schema_version)
      raise UnsupportedVersion, compatibility.reason unless compatibility.compatible

      migrated_attributes = original.deep_dup
      if compatibility.migration_required
        migrated_attributes = migrate_minor_versions(migrated_attributes, from_version, current_schema_version)
      end

      Result.new(
        attributes: migrated_attributes.deep_dup,
        migrated: from_version != migrated_attributes.fetch("schema_version"),
        from_schema_version: from_version,
        to_schema_version: migrated_attributes.fetch("schema_version"),
        rollback_attributes: original.deep_dup,
        rollback_digest: Digest::SHA256.hexdigest(JSON.generate(original))
      )
    end

    def rollback(result)
      result.rollback_attributes.deep_dup
    end

    private

    attr_reader :current_schema_version, :migrators

    def migrate_minor_versions(attributes, from_version, to_version)
      migration = migrators.fetch([ from_version, to_version ]) do
        raise UnsupportedVersion, "no deterministic migrator registered for schema #{from_version} to #{to_version}"
      end

      migrated = migration.call(attributes.deep_dup).deep_stringify_keys
      migrated.fetch("schema_version") == to_version or raise UnsupportedVersion, "schema migrator did not produce #{to_version}"
      migrated
    end
  end
end
