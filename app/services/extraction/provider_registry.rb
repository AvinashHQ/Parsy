# frozen_string_literal: true

module Extraction
  class ProviderRegistry
    Config = Data.define(
      :id,
      :route,
      :configuration_id,
      :provider,
      :provider_id,
      :provider_version,
      :metadata,
      :adapter_request
    ) do
      def initialize(id:, provider:, route: nil, configuration_id: nil, provider_id: nil, provider_version: nil, metadata: {})
        id = id.to_s
        route = (route || id).to_s
        configuration_id = (configuration_id || id).to_s
        provider_id = (provider_id || id).to_s
        provider_version = provider_version&.to_s

        metadata = self.class.content_free_metadata(metadata).merge({
          "provider_id" => id,
          "route" => route,
          "configuration_id" => configuration_id,
          "adapter_provider_id" => provider_id,
          "adapter_provider_version" => provider_version
        }.compact)

        adapter_request = {
          route: route,
          provider_id: provider_id,
          provider_version: provider_version
        }.compact

        super(
          id: id,
          route: route,
          configuration_id: configuration_id,
          provider: provider,
          provider_id: provider_id,
          provider_version: provider_version,
          metadata: self.class.deep_freeze(metadata),
          adapter_request: self.class.deep_freeze(adapter_request)
        )
      end

      def to_h
        {
          id: id,
          route: route,
          configuration_id: configuration_id,
          provider_id: provider_id,
          provider_version: provider_version,
          metadata: metadata
        }.compact
      end

      def self.content_free_metadata(metadata)
        stringify_keys(metadata).slice(
          "provider_id",
          "route",
          "configuration_id",
          "adapter_provider_id",
          "adapter_provider_version"
        )
      end

      def self.stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
        when Array
          value.map { |item| stringify_keys(item) }
        else
          value
        end
      end

      def self.deep_freeze(value)
        case value
        when Hash
          value.each_value { |item| deep_freeze(item) }.freeze
        when Array
          value.each { |item| deep_freeze(item) }.freeze
        else
          value.freeze unless value.nil? || value == true || value == false || value.is_a?(Numeric)
          value
        end
      end
    end

    def initialize(providers:, configurations: {})
      @configs = providers.each_with_object({}) do |(id, provider), configs|
        metadata = provider_metadata(provider).merge(stringify_keys(configurations.fetch(id.to_sym, configurations.fetch(id.to_s, {}))))
        configs[id.to_s] = Config.new(
          id: id,
          provider: provider,
          route: metadata["route"],
          configuration_id: metadata["configuration_id"] || metadata["config_id"],
          provider_id: metadata["adapter_provider_id"] || metadata["provider_id"],
          provider_version: metadata["adapter_provider_version"] || metadata["provider_version"],
          metadata: metadata
        )
      end.freeze
    end

    def fetch(id)
      configs.fetch(id.to_s) { raise KeyError, "unknown provider #{id}" }
    end

    def ids
      configs.keys.sort.freeze
    end

    def all
      ids.map { |id| fetch(id) }.freeze
    end

    private

    attr_reader :configs

    def provider_metadata(provider)
      if provider.respond_to?(:metadata)
        stringify_keys(provider.metadata)
      elsif provider.respond_to?(:to_h)
        stringify_keys(provider.to_h)
      else
        {}
      end
    end

    def stringify_keys(value)
      Config.stringify_keys(value)
    end
  end
end
