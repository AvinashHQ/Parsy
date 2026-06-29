# frozen_string_literal: true

require "yaml"

module Intake
  class FormatRegistry
    Entry = Data.define(:id, :family, :detection, :route, :mvp_status) do
      def self.from_hash(attributes)
        new(
          id: attributes.fetch("id").to_s.freeze,
          family: attributes.fetch("family").to_s.freeze,
          detection: Array(attributes.fetch("detection")).map { |value| value.to_s.freeze }.freeze,
          route: attributes.fetch("route").to_s.freeze,
          mvp_status: attributes.fetch("mvp_status").to_s.freeze
        ).freeze
      end
    end

    attr_reader :version, :unknown_structured_policy, :unknown_visual_policy

    DEFAULT_PATH = Rails.root.join("config/format_registry.yml")

    def self.load(path: DEFAULT_PATH)
      attributes = YAML.safe_load(Pathname(path).read, aliases: false)
      new(attributes)
    end

    def initialize(attributes)
      @version = attributes.fetch("version").to_s.freeze
      @formats = Array(attributes.fetch("formats")).map { |format| Entry.from_hash(format) }.freeze
      @formats_by_id = @formats.to_h { |format| [ format.id, format ] }.freeze
      @unknown_structured_policy = attributes.fetch("unknown_structured_policy", "quarantine").to_s.freeze
      @unknown_visual_policy = attributes.fetch("unknown_visual_policy", "reject_or_operator_review").to_s.freeze
      freeze
    end

    def formats
      @formats
    end

    def find(id)
      @formats_by_id.fetch(id.to_s)
    end
  end
end
