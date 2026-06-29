# frozen_string_literal: true

require "digest"
require "json"
require "set"

module Extraction
  class ProviderAdapter
    JSON_INVALID = "JSON_INVALID"
    SCHEMA_INVALID = "SCHEMA_INVALID"
    REPAIR_LIMIT_EXCEEDED = "REPAIR_LIMIT_EXCEEDED"
    REPAIR_PATH_NOT_ALLOWED = "REPAIR_PATH_NOT_ALLOWED"
    REPAIR_EMPTY_PATCH = "REPAIR_EMPTY_PATCH"
    COST_LIMIT_PAUSED = "COST_LIMIT_PAUSED"


    ProviderResponse = Data.define(:json_text, :metadata)

    ProcessingAttempt = Data.define(
      :status,
      :error_code,
      :source_sha256,
      :route,
      :region,
      :schema_version,
      :prompt_id,
      :prompt_sha256,
      :provider,
      :provider_version,
      :model,
      :model_version,
      :cost,
      :input_tokens,
      :output_tokens,
      :latency_ms,
      :idempotency_key,
      :repair_attempt,
      :schema_error_count,
      :schema_error_pointers,
      :schema_error_types
    ) do
      def success?
        status == :accepted
      end

      def failed?
        status == :rejected
      end
    end

    Result = Data.define(
      :status,
      :candidate,
      :attributes,
      :attempts,
      :idempotency_key,
      :cached,
      :error_code,
      :repair_attempts
    ) do
      def success?
        status == :accepted
      end

      def rejected?
        status == :rejected
      end

      def cached?
        cached
      end
    end

    CandidateRecord = Data.define(:candidate, :attributes)

    def initialize(provider:, schema_validator: Canonical::SchemaValidator.new, cache: {}, quota_guard: nil)
      @provider = provider
      @schema_validator = schema_validator
      @cache = cache
      @quota_guard = quota_guard
    end

    def extract(source_sha256:, route:, region: nil, prompt_id: nil, prompt: nil, schema_version: Canonical::Invoice::SCHEMA_VERSION,
                provider_id: nil, provider_version: nil, model: nil, model_version: nil, route_profile_version: nil,
                region_pack_version: nil, estimated_cost_cents: 0, **provider_request)
      prompt_identifier = prompt_identifier(prompt_id:, prompt:)
      prompt_sha256 = sha256(prompt_identifier)
      provider_identifier = provider_identifier(provider_id:, provider_version:)
      region_identifier = region_pack_version || region
      idempotency_key = idempotency_key_for(
        source_sha256:,
        schema_version:,
        route_profile_version: route_profile_version || route,
        provider_identifier:,
        prompt_sha256:,
        region_pack_version: region_identifier
      )

      if (record = cache[idempotency_key])
        return Result.new(
          status: :accepted,
          candidate: record.candidate,
          attributes: deep_copy(record.attributes),
          attempts: [],
          idempotency_key:,
          cached: true,
          error_code: nil,
          repair_attempts: 0
        )
      end

      if quota_guard
        quota = quota_guard.reserve!(
          provider: provider_identifier,
          estimated_cents: estimated_cost_cents.to_i,
          idempotency_key:,
          metadata: { route:, region:, model: }.compact
        )
        unless quota.allowed
          attempt = processing_attempt(
            status: :rejected,
            error_code: COST_LIMIT_PAUSED,
            source_sha256:,
            route:,
            region:,
            schema_version:,
            prompt_id: prompt_identifier,
            prompt_sha256:,
            provider_identifier:,
            provider_version:,
            model:,
            model_version:,
            idempotency_key:,
            metadata: { cost: estimated_cost_cents.to_i },
            repair_attempt: 0
          )
          return rejected_result(error_code: COST_LIMIT_PAUSED, attributes: nil, attempts: [ attempt ], idempotency_key:, repair_attempts: 0)
        end
      end

      response = normalize_response(call_provider(provider_request.merge(
        source_sha256:,
        route:,
        region:,
        schema_version:,
        prompt_id: prompt_identifier,
        prompt_sha256:,
        provider_id: provider_identifier,
        provider_version:,
        model:,
        model_version:
      )))
      provider_metadata = normalize_metadata(response.metadata)
      attributes = parse_json(response.json_text)

      unless attributes.is_a?(Hash)
        attempt = processing_attempt(
          status: :rejected,
          error_code: JSON_INVALID,
          source_sha256:,
          route:,
          region:,
          schema_version:,
          prompt_id: prompt_identifier,
          prompt_sha256:,
          provider_identifier:,
          provider_version:,
          model:,
          model_version:,
          idempotency_key:,
          metadata: provider_metadata,
          repair_attempt: 0
        )
        return rejected_result(error_code: JSON_INVALID, attributes: nil, attempts: [ attempt ], idempotency_key:, repair_attempts: 0)
      end

      build_result(
        attributes:,
        attempts: [],
        source_sha256:,
        route:,
        region:,
        schema_version:,
        prompt_id: prompt_identifier,
        prompt_sha256:,
        provider_identifier:,
        provider_version:,
        model:,
        model_version:,
        idempotency_key:,
        metadata: provider_metadata,
        repair_attempt: 0,
        cache_success: true
      )
    rescue JSON::ParserError
      metadata = defined?(provider_metadata) ? provider_metadata : {}
      attempt = processing_attempt(
        status: :rejected,
        error_code: JSON_INVALID,
        source_sha256:,
        route:,
        region:,
        schema_version:,
        prompt_id: prompt_identifier,
        prompt_sha256:,
        provider_identifier:,
        provider_version:,
        model:,
        model_version:,
        idempotency_key:,
        metadata:,
        repair_attempt: 0
      )
      rejected_result(error_code: JSON_INVALID, attributes: nil, attempts: [ attempt ], idempotency_key:, repair_attempts: 0)
    end

    def repair(result:, patch:, allowed_paths:)
      return repair_rejection(result, REPAIR_LIMIT_EXCEEDED) if result.repair_attempts >= 1

      normalized_patch = parse_patch(patch)
      changed_paths = merge_patch_leaf_paths(normalized_patch)
      return repair_rejection(result, REPAIR_EMPTY_PATCH) if changed_paths.empty?

      allowed = allowed_paths.map { |path| normalize_pointer(path) }.to_set
      return repair_rejection(result, REPAIR_PATH_NOT_ALLOWED) unless changed_paths.all? { |path| allowed.include?(path) }

      attributes = result.attributes || result.candidate&.to_h
      repaired_attributes = apply_merge_patch(deep_copy(attributes), normalized_patch)
      last_attempt = result.attempts.last

      build_result(
        attributes: repaired_attributes,
        attempts: result.attempts,
        source_sha256: last_attempt&.source_sha256,
        route: last_attempt&.route,
        region: last_attempt&.region,
        schema_version: last_attempt&.schema_version || Canonical::Invoice::SCHEMA_VERSION,
        prompt_id: last_attempt&.prompt_id,
        prompt_sha256: last_attempt&.prompt_sha256,
        provider_identifier: last_attempt&.provider,
        provider_version: last_attempt&.provider_version,
        model: last_attempt&.model,
        model_version: last_attempt&.model_version,
        idempotency_key: result.idempotency_key,
        metadata: {},
        repair_attempt: result.repair_attempts + 1,
        cache_success: false,
        existing_repair_attempts: result.repair_attempts + 1
      )
    rescue JSON::ParserError
      repair_rejection(result, JSON_INVALID)
    end

    private

    attr_reader :provider, :schema_validator, :cache, :quota_guard

    def prompt_identifier(prompt_id:, prompt:)
      identifier = prompt_id || prompt
      raise ArgumentError, "prompt_id is required" if identifier.to_s.empty?

      identifier.to_s
    end

    def provider_identifier(provider_id:, provider_version:)
      explicit = provider_id || provider_name(provider)
      [ explicit, provider_version ].compact.join("@")
    end

    def provider_name(provider)
      return provider.name.to_s if provider.respond_to?(:name) && !provider.name.to_s.empty?

      provider.class.name.to_s
    end

    def idempotency_key_for(source_sha256:, schema_version:, route_profile_version:, provider_identifier:, prompt_sha256:, region_pack_version:)
      sha256([
        source_sha256,
        schema_version,
        route_profile_version,
        provider_identifier,
        prompt_sha256,
        region_pack_version
      ].map(&:to_s).join("\0"))
    end

    def sha256(value)
      Digest::SHA256.hexdigest(value.to_s)
    end

    def call_provider(request)
      if provider.respond_to?(:call)
        call_method = provider.method(:call)
        if call_method.parameters.any? { |kind, _name| %i[key keyreq keyrest].include?(kind) }
          call_method.call(**request)
        else
          call_method.call(request)
        end
      elsif provider.respond_to?(:extract)
        provider.extract(request)
      else
        raise ArgumentError, "provider must respond to call or extract"
      end
    end

    def normalize_response(response)
      return response if response.is_a?(ProviderResponse)

      if response.respond_to?(:json_text)
        return ProviderResponse.new(json_text: response.json_text, metadata: response.respond_to?(:metadata) ? response.metadata : {})
      end

      if response.is_a?(Hash)
        return ProviderResponse.new(
          json_text: response[:json_text] || response["json_text"] || response[:body] || response["body"] || response[:content] || response["content"],
          metadata: response[:metadata] || response["metadata"] || {}
        )
      end

      if response.is_a?(Array)
        return ProviderResponse.new(json_text: response[0], metadata: response[1] || {})
      end

      ProviderResponse.new(json_text: response.to_s, metadata: {})
    end

    def normalize_metadata(metadata)
      metadata = metadata.to_h if metadata.respond_to?(:to_h)
      metadata = {} unless metadata.is_a?(Hash)
      metadata.transform_keys(&:to_sym)
    end

    def parse_json(json_text)
      JSON.parse(json_text.to_s)
    end

    def parse_patch(patch)
      parsed = patch.is_a?(String) ? JSON.parse(patch) : patch
      unless parsed.is_a?(Hash)
        raise JSON::ParserError, "merge patch must be a JSON object"
      end

      stringify_keys(parsed)
    end

    def build_result(attributes:, attempts:, source_sha256:, route:, region:, schema_version:, prompt_id:, prompt_sha256:,
                     provider_identifier:, provider_version:, model:, model_version:, idempotency_key:, metadata:,
                     repair_attempt:, cache_success:, existing_repair_attempts: repair_attempt)
      errors = schema_validator.validate(attributes)
      status = errors.empty? ? :accepted : :rejected
      error_code = errors.empty? ? nil : SCHEMA_INVALID
      attempt = processing_attempt(
        status:,
        error_code:,
        source_sha256:,
        route:,
        region:,
        schema_version:,
        prompt_id:,
        prompt_sha256:,
        provider_identifier:,
        provider_version:,
        model:,
        model_version:,
        idempotency_key:,
        metadata:,
        repair_attempt:,
        schema_errors: errors
      )
      all_attempts = attempts + [ attempt ]

      if errors.empty?
        candidate = Canonical::Invoice.from_hash(attributes)
        cache[idempotency_key] = CandidateRecord.new(candidate:, attributes: deep_copy(attributes)) if cache_success

        Result.new(
          status:,
          candidate:,
          attributes: candidate.to_h,
          attempts: all_attempts,
          idempotency_key:,
          cached: false,
          error_code: nil,
          repair_attempts: existing_repair_attempts
        )
      else
        rejected_result(
          error_code:,
          attributes: deep_copy(attributes),
          attempts: all_attempts,
          idempotency_key:,
          repair_attempts: existing_repair_attempts
        )
      end
    end

    def processing_attempt(status:, error_code:, source_sha256:, route:, region:, schema_version:, prompt_id:, prompt_sha256:,
                           provider_identifier:, provider_version:, model:, model_version:, idempotency_key:, metadata:,
                           repair_attempt:, schema_errors: [])
      tokens = normalize_metadata(metadata[:tokens] || {})
      ProcessingAttempt.new(
        status:,
        error_code:,
        source_sha256:,
        route:,
        region:,
        schema_version:,
        prompt_id:,
        prompt_sha256:,
        provider: provider_identifier,
        provider_version: metadata[:provider_version] || metadata[:version] || provider_version,
        model: metadata[:model] || model,
        model_version: metadata[:model_version] || model_version,
        cost: metadata[:cost],
        input_tokens: metadata[:input_tokens] || tokens[:input] || tokens[:prompt],
        output_tokens: metadata[:output_tokens] || tokens[:output] || tokens[:completion],
        latency_ms: metadata[:latency_ms],
        idempotency_key:,
        repair_attempt:,
        schema_error_count: schema_errors.size,
        schema_error_pointers: schema_errors.map(&:data_pointer).uniq.sort,
        schema_error_types: schema_errors.map(&:type).uniq.compact.sort
      )
    end

    def rejected_result(error_code:, attributes:, attempts:, idempotency_key:, repair_attempts:)
      Result.new(
        status: :rejected,
        candidate: nil,
        attributes:,
        attempts:,
        idempotency_key:,
        cached: false,
        error_code:,
        repair_attempts:
      )
    end

    def repair_rejection(result, error_code)
      rejected_result(
        error_code:,
        attributes: result.attributes,
        attempts: result.attempts,
        idempotency_key: result.idempotency_key,
        repair_attempts: result.repair_attempts
      )
    end

    def merge_patch_leaf_paths(object, prefix = "")
      object.flat_map do |key, value|
        pointer = "#{prefix}/#{escape_pointer(key)}"
        if value.is_a?(Hash) && value.any?
          merge_patch_leaf_paths(value, pointer)
        elsif value.is_a?(Hash)
          []
        else
          [ pointer ]
        end
      end
    end

    def apply_merge_patch(target, patch)
      patch.each do |key, value|
        if value.nil?
          target.delete(key)
        elsif value.is_a?(Hash)
          existing = target[key].is_a?(Hash) ? target[key] : {}
          target[key] = apply_merge_patch(existing, value)
        else
          target[key] = deep_copy(value)
        end
      end
      target
    end

    def normalize_pointer(path)
      pointer = path.to_s
      pointer.start_with?("/") ? pointer : "/#{pointer}"
    end

    def escape_pointer(value)
      value.to_s.gsub("~", "~0").gsub("/", "~1")
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

    def deep_copy(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key] = deep_copy(item) }
      when Array
        value.map { |item| deep_copy(item) }
      else
        value
      end
    end
  end
end
