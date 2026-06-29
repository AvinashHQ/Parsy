# frozen_string_literal: true

module Extraction
  class ProviderSelection
    SelectedProvider = Data.define(:id, :enabled, :route, :configuration_id, :provider, :metadata, :adapter_request) do
      def enabled? = enabled

      def to_h
        {
          id: id,
          enabled: enabled,
          route: route,
          configuration_id: configuration_id,
          metadata: metadata,
          adapter_request: adapter_request
        }
      end
    end

    Result = Data.define(:selected, :rolled_back, :available) do
      def provider = selected.provider
      def adapter_request = selected.adapter_request
      def metadata = selected.metadata
      def local_open_source? = selected.id == "local_open_source"
      def existing_provider? = selected.id == "existing_provider"
      def fixture? = selected.id == "fixture"

      def to_h
        {
          selected: selected.to_h,
          rolled_back: rolled_back,
          available: available.map(&:to_h)
        }
      end
    end

    def initialize(providers: nil, registry: nil, flags: {}, default_provider_id: "existing_provider", configurations: {})
      raise ArgumentError, "providers or registry is required" if providers.nil? && registry.nil?

      @registry = registry || ProviderRegistry.new(providers: providers, configurations: configurations)
      @flags = stringify_keys(flags)
      @default_provider_id = default_provider_id.to_s
    end

    def select(requested: nil, requested_route: nil, tenant_flags: {})
      merged_flags = flags.merge(stringify_keys(tenant_flags))
      local_enabled = truthy?(merged_flags.fetch("local_open_source", false))
      requested_id = (requested || requested_route).to_s
      requested_id = merged_flags.fetch("provider", default_provider_id) if requested_id.empty?
      selected_id = requested_id
      selected_id = "existing_provider" if selected_id == "local_open_source" && !local_enabled
      rolled_back = requested_id == "local_open_source" && selected_id != "local_open_source"

      Result.new(
        selected: selected_provider(registry.fetch(selected_id), requested_id:, enabled: enabled?(selected_id, local_enabled), rolled_back:, local_enabled:),
        rolled_back: rolled_back,
        available: registry.all.map { |config| selected_provider(config, requested_id: config.id, enabled: enabled?(config.id, local_enabled), rolled_back: false, local_enabled:) }
      )
    end

    private

    attr_reader :registry, :flags, :default_provider_id

    def selected_provider(config, requested_id:, enabled:, rolled_back:, local_enabled:)
      metadata = deep_freeze(config.metadata.merge(
        "requested_provider_id" => requested_id,
        "selected_provider_id" => config.id,
        "rolled_back" => rolled_back,
        "local_open_source_enabled" => local_enabled
      ))

      SelectedProvider.new(
        id: config.id,
        enabled: enabled,
        route: config.route,
        configuration_id: config.configuration_id,
        provider: config.provider,
        metadata: metadata,
        adapter_request: config.adapter_request
      )
    end

    def enabled?(id, local_enabled)
      id != "local_open_source" || local_enabled
    end

    def truthy?(value)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end

    def deep_freeze(value)
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
end
