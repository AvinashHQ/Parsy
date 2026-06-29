# frozen_string_literal: true

require "digest"
require "json"
require "timeout"

module LocalExtraction
  class QwenSemanticAdapter
    PROMPT_ID = "local_qwen3_vl_invoice_v2"
    PROMPT = <<~PROMPT.freeze
      Extract one invoice or credit note as Canonical Invoice v2 JSON only.
      Preserve nulls for absent optional fields, keep ambiguous fields null, and return no explanation.
      Do not use model confidence to accept or reject the result; schema validation is authoritative.
    PROMPT
    PROMPT_SHA256 = Digest::SHA256.hexdigest(PROMPT)
    PROVIDER_ID = "local_open_source"
    PROVIDER_VERSION = "qwen3-vl-boundary-v1"
    MODEL = "qwen3-vl"
    DEFAULT_MODEL_REVISION = "qwen3-vl-local-fixture"
    DEFAULT_QUANTIZATION = "fixture-int4"
    DEFAULT_RUNTIME = "fixture"
    DEFAULT_DEVICE = "cpu"
    DEFAULT_TIMEOUT_MS = 30_000
    DEFAULT_DETERMINISTIC_SETTINGS = {
      temperature: 0,
      top_p: 1,
      top_k: 1,
      seed: 0,
      max_repair_attempts: 1
    }.freeze

    class OutOfMemory < StandardError; end
    class CorruptDocument < StandardError; end

    class SemanticResult
      attr_reader :status, :candidate, :attributes, :attempts, :idempotency_key, :cached, :error_code,
                  :repair_attempts, :provenance, :failure, :provider_result

      def initialize(status:, candidate:, attributes:, attempts:, idempotency_key:, cached:, error_code:, repair_attempts:, provenance:, failure:, provider_result:)
        @status = status.to_s
        @candidate = candidate
        @attributes = attributes
        @attempts = attempts.freeze
        @idempotency_key = idempotency_key
        @cached = cached
        @error_code = error_code
        @repair_attempts = repair_attempts
        @provenance = SafeFailure.content_free(provenance)
        @failure = failure
        @provider_result = provider_result
      end

      def success? = status == "accepted"
      def rejected? = !success?
      def cached? = cached
      def failed? = status == "failed"
      def quarantined? = status == "quarantined"
      def needs_review? = status == "needs_review"

      def to_h
        {
          status: status,
          attributes: success? ? attributes : nil,
          idempotency_key: idempotency_key,
          cached: cached,
          error_code: error_code,
          repair_attempts: repair_attempts,
          provenance: provenance,
          failure: failure&.to_h,
          attempts: attempts.map(&:to_h)
        }.compact
      end
    end

    ProviderBoundary = Struct.new(:client, :adapter, keyword_init: true) do
      def call(**request)
        adapter.call_local_client(client:, request:)
      end
    end

    attr_reader :client, :cache, :model_revision, :quantization, :runtime, :device, :timeout_ms,
                :deterministic_settings

    def initialize(client:, cache: {}, provider_adapter: nil, model_revision: DEFAULT_MODEL_REVISION,
                   quantization: DEFAULT_QUANTIZATION, runtime: DEFAULT_RUNTIME, device: DEFAULT_DEVICE,
                   timeout_ms: DEFAULT_TIMEOUT_MS, deterministic_settings: {})
      @client = client
      @cache = cache
      @model_revision = model_revision.to_s
      @quantization = quantization.to_s
      @runtime = runtime.to_s
      @device = device.to_s
      @timeout_ms = Integer(timeout_ms)
      @deterministic_settings = DEFAULT_DETERMINISTIC_SETTINGS.merge(symbolize_keys(deterministic_settings)).freeze
      @provider_adapter = provider_adapter || Extraction::ProviderAdapter.new(
        provider: ProviderBoundary.new(client:, adapter: self),
        cache:
      )
    end

    def extract(inspection:, parser_output: {}, ocr_output: {})
      request_context = request_context(inspection:, parser_output:, ocr_output:)
      provider_result = provider_adapter.extract(**provider_request(request_context))

      semantic_result_from(provider_result:, route: request_context.fetch(:route), provenance: provenance_for(request_context, provider_result:))
    rescue JSON::ParserError
      failure_result(code: SafeFailure::JSON_INVALID, route: safe_route(inspection), context: request_context_or_empty(binding))
    rescue Timeout::Error
      failure_result(code: SafeFailure::TIMEOUT, route: safe_route(inspection), context: request_context_or_empty(binding))
    rescue OutOfMemory, NoMemoryError
      failure_result(code: SafeFailure::OUT_OF_MEMORY, route: safe_route(inspection), context: request_context_or_empty(binding))
    rescue CorruptDocument
      failure_result(code: SafeFailure::CORRUPT_DOCUMENT, route: safe_route(inspection), context: request_context_or_empty(binding))
    end

    def repair(result:, inspection:, allowed_paths:, parser_output: {}, ocr_output: {})
      provider_result = result.provider_result
      return repair_rejection(result:, code: SafeFailure::REPAIR_UNAVAILABLE, inspection:) unless provider_result

      if provider_result.repair_attempts >= 1
        limited = provider_adapter.repair(result: provider_result, patch: {}, allowed_paths: allowed_paths)
        return semantic_result_from(
          provider_result: limited,
          route: safe_route(inspection),
          provenance: result.provenance.merge(repair_attempts: limited.repair_attempts)
        )
      end

      request_context = request_context(inspection:, parser_output:, ocr_output:)
      patch = local_repair_patch(
        result:,
        request_context:,
        allowed_paths: allowed_paths.map { |path| normalize_pointer(path) }
      )
      repaired = provider_adapter.repair(result: provider_result, patch:, allowed_paths:)

      semantic_result_from(
        provider_result: repaired,
        route: request_context.fetch(:route),
        provenance: provenance_for(request_context, provider_result: repaired).merge(repair_attempts: repaired.repair_attempts)
      )
    rescue JSON::ParserError
      repair_rejection(result:, code: SafeFailure::JSON_INVALID, inspection:)
    rescue Timeout::Error
      repair_rejection(result:, code: SafeFailure::TIMEOUT, inspection:)
    rescue OutOfMemory, NoMemoryError
      repair_rejection(result:, code: SafeFailure::OUT_OF_MEMORY, inspection:)
    end

    def call_local_client(client:, request:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = invoke_client(client, request)
      normalized = normalize_client_response(response)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      {
        json_text: normalized.fetch(:json_text),
        metadata: client_metadata(normalized.fetch(:metadata), latency_ms: normalized.fetch(:metadata)[:latency_ms] || elapsed_ms)
      }
    end

    private

    attr_reader :provider_adapter

    def invoke_client(client, request)
      if client.respond_to?(:extract_invoice)
        client.extract_invoice(client_request(request))
      elsif client.respond_to?(:call)
        client.call(client_request(request))
      else
        raise ArgumentError, "local semantic client must respond to extract_invoice or call"
      end
    end

    def local_repair_patch(result:, request_context:, allowed_paths:)
      unless client.respond_to?(:repair_invoice)
        return {}
      end

      response = client.repair_invoice(
        repair_request(
          result:,
          request_context:,
          allowed_paths:
        )
      )
      normalized = normalize_repair_response(response)
      normalized.fetch(:patch)
    end

    def request_context(inspection:, parser_output:, ocr_output:)
      parser = hash_like(parser_output)
      ocr = hash_like(ocr_output)
      raise CorruptDocument if corrupt_output?(parser) || corrupt_output?(ocr)

      detection = inspection.detection
      {
        source_sha256: inspection.sha256,
        byte_size: inspection.byte_size,
        route: detection&.route.to_s,
        family: detection&.family,
        profile: detection&.profile,
        detection_version: detection&.version,
        page_count: parser[:page_count] || ocr[:page_count],
        parser_version: parser[:version],
        ocr_version: ocr[:version],
        parser_output: parser,
        ocr_output: ocr
      }
    end

    def provider_request(context)
      {
        source_sha256: context.fetch(:source_sha256),
        route: context.fetch(:route),
        region: context[:profile],
        schema_version: Canonical::Invoice::SCHEMA_VERSION,
        prompt: PROMPT,
        provider_id: PROVIDER_ID,
        model: MODEL,
        model_version: model_revision,
        route_profile_version: route_profile_version(context),
        region_pack_version: context[:detection_version],
        document: {
          source_sha256: context.fetch(:source_sha256),
          byte_size: context[:byte_size],
          family: context[:family],
          profile: context[:profile],
          route: context[:route],
          page_count: context[:page_count]
        }.compact,
        parser_output: context.fetch(:parser_output),
        ocr_output: context.fetch(:ocr_output),
        deterministic_settings: deterministic_settings,
        prompt_sha256: PROMPT_SHA256,
        timeout_ms: timeout_ms
      }
    end

    def client_request(request)
      {
        prompt_id: PROMPT_ID,
        prompt: PROMPT,
        prompt_sha256: PROMPT_SHA256,
        schema_version: request.fetch(:schema_version),
        document: request.fetch(:document),
        parser_output: request.fetch(:parser_output),
        ocr_output: request.fetch(:ocr_output),
        deterministic_settings: deterministic_settings,
        timeout_ms: timeout_ms,
        model: MODEL,
        model_revision: model_revision,
        quantization: quantization,
        runtime: runtime,
        device: device
      }
    end

    def repair_request(result:, request_context:, allowed_paths:)
      {
        prompt_id: PROMPT_ID,
        prompt_sha256: PROMPT_SHA256,
        schema_version: Canonical::Invoice::SCHEMA_VERSION,
        document: {
          source_sha256: request_context.fetch(:source_sha256),
          byte_size: request_context[:byte_size],
          family: request_context[:family],
          profile: request_context[:profile],
          route: request_context[:route],
          page_count: request_context[:page_count]
        }.compact,
        allowed_paths: allowed_paths,
        error_code: result.error_code,
        schema_error_pointers: result.attempts.last&.schema_error_pointers || [],
        schema_error_types: result.attempts.last&.schema_error_types || [],
        deterministic_settings: deterministic_settings,
        timeout_ms: timeout_ms,
        model: MODEL,
        model_revision: model_revision,
        quantization: quantization,
        runtime: runtime,
        device: device
      }
    end

    def semantic_result_from(provider_result:, route:, provenance:)
      status = provider_result.success? ? "accepted" : "needs_review"
      failure = provider_result.success? ? nil : failure_for_provider_result(provider_result, route:)
      attributes = provider_result.success? ? provider_result.attributes : nil

      SemanticResult.new(
        status: status,
        candidate: provider_result.candidate,
        attributes: attributes,
        attempts: provider_result.attempts,
        idempotency_key: provider_result.idempotency_key,
        cached: provider_result.cached?,
        error_code: provider_result.error_code,
        repair_attempts: provider_result.repair_attempts,
        provenance: provenance,
        failure: failure,
        provider_result: provider_result
      )
    end

    def failure_for_provider_result(provider_result, route:)
      last_attempt = provider_result.attempts.last
      SafeFailure.for_code(
        provider_result.error_code,
        route:,
        metadata: {
          error_code: provider_result.error_code,
          idempotency_key: provider_result.idempotency_key,
          repair_attempts: provider_result.repair_attempts,
          schema_error_count: last_attempt&.schema_error_count,
          schema_error_pointers: last_attempt&.schema_error_pointers,
          schema_error_types: last_attempt&.schema_error_types
        }
      )
    end

    def failure_result(code:, route:, context: {})
      failure = SafeFailure.for_code(code, route:, metadata: provenance_for(context).merge(error_code: code))
      SemanticResult.new(
        status: failure.status,
        candidate: nil,
        attributes: nil,
        attempts: [],
        idempotency_key: nil,
        cached: false,
        error_code: code,
        repair_attempts: 0,
        provenance: failure.metadata,
        failure: failure,
        provider_result: nil
      )
    end

    def repair_rejection(result:, code:, inspection:)
      failure = SafeFailure.for_code(code, route: safe_route(inspection), metadata: result.provenance.merge(error_code: code))
      SemanticResult.new(
        status: failure.status,
        candidate: nil,
        attributes: nil,
        attempts: result.attempts,
        idempotency_key: result.idempotency_key,
        cached: false,
        error_code: code,
        repair_attempts: result.repair_attempts,
        provenance: failure.metadata,
        failure: failure,
        provider_result: result.provider_result
      )
    end

    def provenance_for(context, provider_result: nil)
      last_attempt = provider_result&.attempts&.last
      SafeFailure.content_free(
        {
          source_sha256: context[:source_sha256],
          route: context[:route],
          family: context[:family],
          profile: context[:profile],
          detection_version: context[:detection_version],
          byte_size: context[:byte_size],
          page_count: context[:page_count],
          parser_version: context[:parser_version],
          ocr_version: context[:ocr_version],
          model: MODEL,
          model_revision: model_revision,
          quantization: quantization,
          runtime: runtime,
          prompt_sha256: PROMPT_SHA256,
          device: device,
          latency_ms: last_attempt&.latency_ms,
          idempotency_key: provider_result&.idempotency_key,
          repair_attempts: provider_result&.repair_attempts,
          error_code: provider_result&.error_code,
          schema_error_count: last_attempt&.schema_error_count,
          schema_error_pointers: last_attempt&.schema_error_pointers,
          schema_error_types: last_attempt&.schema_error_types
        }
      )
    end

    def client_metadata(metadata, latency_ms:)
      SafeFailure.content_free(metadata).merge(
        provider_version: provider_version,
        model: MODEL,
        model_version: model_revision,
        latency_ms: latency_ms,
        model_revision: model_revision,
        quantization: quantization,
        runtime: runtime,
        prompt_sha256: PROMPT_SHA256,
        device: device
      )
    end

    def normalize_client_response(response)
      if response.respond_to?(:json_text)
        return {
          json_text: response.json_text,
          metadata: symbolize_keys(response.respond_to?(:metadata) ? response.metadata : {})
        }
      end

      if response.is_a?(Hash)
        metadata = response[:metadata] || response["metadata"] || {}
        return {
          json_text: response[:json_text] || response["json_text"] || response[:body] || response["body"] || response[:content] || response["content"],
          metadata: symbolize_keys(metadata)
        }
      end

      { json_text: response.to_s, metadata: {} }
    end

    def normalize_repair_response(response)
      if response.is_a?(Hash)
        patch = response.key?(:patch) ? response[:patch] : response["patch"]
        return { patch: patch || response }
      end

      { patch: JSON.parse(response.to_s) }
    end

    def provider_version
      [ PROVIDER_VERSION, runtime, quantization ].join("/")
    end

    def route_profile_version(context)
      Digest::SHA256.hexdigest([
        context[:route],
        context[:family],
        context[:profile],
        context[:detection_version],
        model_revision,
        quantization,
        runtime,
        device,
        PROMPT_SHA256,
        deterministic_settings.sort.to_h.to_json
      ].map(&:to_s).join("\0"))
    end

    def corrupt_output?(output)
      output[:corrupt] || output[:status].to_s == "corrupt" || Array(output[:errors]).map(&:to_s).include?(SafeFailure::CORRUPT_DOCUMENT)
    end

    def hash_like(value)
      raw = value.respond_to?(:to_h) ? value.to_h : value
      raw = {} unless raw.is_a?(Hash)
      symbolize_keys(raw)
    end

    def symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_sym] = symbolize_keys(item) }
      when Array
        value.map { |item| symbolize_keys(item) }
      else
        value
      end
    end

    def normalize_pointer(path)
      pointer = path.to_s
      pointer.start_with?("/") ? pointer : "/#{pointer}"
    end

    def safe_route(inspection)
      inspection&.route.to_s.empty? ? "local_open_source" : inspection.route.to_s
    end

    def request_context_or_empty(binding_object)
      value = binding_object.local_variable_defined?(:request_context) ? binding_object.local_variable_get(:request_context) : {}
      value.is_a?(Hash) ? value : {}
    end
  end
end
