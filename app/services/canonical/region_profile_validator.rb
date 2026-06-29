# frozen_string_literal: true

require "json"
require "json_schemer"
require "yaml"

module Canonical
  class RegionProfileValidator
    Error = Data.define(:profile_id, :data_pointer, :schema_pointer, :type, :details) do
      def message
        details.fetch("error", type.to_s)
      end
    end

    SCHEMA_PATH = Rails.root.join("contracts/region_profile.schema.json")
    CONFIG_PATH = Rails.root.join("config/region_profiles.yml")

    def initialize(schema_path: SCHEMA_PATH, config_path: CONFIG_PATH)
      @schema_path = Pathname(schema_path)
      @config_path = Pathname(config_path)
    end

    def valid?(profile)
      validate(profile).empty?
    end

    def validate(profile)
      profile_id = profile["id"] || profile[:id]
      schemer.validate(profile.deep_stringify_keys).map do |error|
        Error.new(
          profile_id: profile_id,
          data_pointer: error.fetch("data_pointer", ""),
          schema_pointer: error.fetch("schema_pointer", ""),
          type: error.fetch("type", nil),
          details: error
        )
      end
    end

    def configured_profiles
      config.fetch("profiles").map(&:deep_stringify_keys)
    end

    def validate_configured_profiles
      configured_profiles.to_h { |profile| [ profile.fetch("id"), validate(profile) ] }
    end

    private

    attr_reader :schema_path, :config_path

    def config
      @config ||= YAML.safe_load(config_path.read, permitted_classes: [], aliases: false).deep_stringify_keys
    end

    def schemer
      @schemer ||= JSONSchemer.schema(JSON.parse(schema_path.read))
    end
  end
end
