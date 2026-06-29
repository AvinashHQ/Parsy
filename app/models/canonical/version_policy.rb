# frozen_string_literal: true

module Canonical
  class VersionPolicy
    CURRENT_SCHEMA_VERSION = "2.0"
    CURRENT_PROFILE_ID = "global_generic_v1"
    CURRENT_PROFILE_VERSION = "1.0.0"

    Compatibility = Data.define(:compatible, :migration_required, :reason)
    Version = Data.define(:major, :minor, :patch)

    def self.schema_compatibility(schema_version)
      parsed = parse_version(schema_version, parts: 2)
      return incompatible("schema version is not major.minor") unless parsed

      current = parse_version(CURRENT_SCHEMA_VERSION, parts: 2)
      compare_major_minor(parsed, current, "schema")
    end

    def self.profile_compatibility(profile_id:, profile_version:)
      return incompatible("profile id is not #{CURRENT_PROFILE_ID}") unless profile_id == CURRENT_PROFILE_ID

      parsed = parse_version(profile_version, parts: 3)
      return incompatible("profile version is not semantic major.minor.patch") unless parsed

      current = parse_version(CURRENT_PROFILE_VERSION, parts: 3)
      compare_major_minor(parsed, current, "profile")
    end

    def self.invoice_compatibility(invoice)
      schema = schema_compatibility(invoice.schema_version)
      return schema unless schema.compatible

      profile = profile_compatibility(
        profile_id: invoice.locale&.applied_region_pack_id,
        profile_version: invoice.locale&.applied_region_pack_version
      )
      return profile unless profile.compatible

      Compatibility.new(compatible: true, migration_required: schema.migration_required || profile.migration_required, reason: "compatible")
    end

    def self.compatible_invoice?(invoice)
      invoice_compatibility(invoice).compatible
    end

    def self.parse_version(version, parts:)
      segments = version.to_s.split(".")
      return nil unless segments.length == parts && segments.all? { |segment| segment.match?(/\A\d+\z/) }

      numbers = segments.map(&:to_i)
      Version.new(major: numbers[0], minor: numbers[1], patch: numbers[2])
    end
    private_class_method :parse_version

    def self.compare_major_minor(candidate, current, label)
      return incompatible("unsupported #{label} major version") unless candidate.major == current.major
      return incompatible("future #{label} minor version") if candidate.minor > current.minor

      Compatibility.new(
        compatible: true,
        migration_required: candidate.minor < current.minor,
        reason: candidate.minor < current.minor ? "#{label} minor migration required" : "compatible"
      )
    end
    private_class_method :compare_major_minor

    def self.incompatible(reason)
      Compatibility.new(compatible: false, migration_required: false, reason: reason)
    end
    private_class_method :incompatible
  end
end
