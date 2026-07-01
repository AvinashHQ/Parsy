# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "base64"

module RemoteVision
  # Cloud vision provider (Google Gemini) driven through the frozen M2 provider
  # contract (ADR-026). It answers the SAME interface as
  # LocalExtraction::OllamaClient — #extract_invoice(request) (aliased #call)
  # returning { json_text:, metadata: } — so Extraction::ProviderAdapter, which
  # owns JSON parsing and schema validation, can drop it in beside the local
  # client without any other change.
  #
  # The client composes the shared prompt (field contract + worked example) plus
  # the parser/OCR text and page image(s) into one Gemini generateContent
  # request, asks for JSON output, and returns the model's raw text unmodified.
  # It never decides acceptance and never logs invoice content.
  #
  # Cloud egress is opt-in and tenant-disclosed (ADR-026); the API key is a
  # managed secret read from ENV (this project keeps all config in ENV, not Rails
  # encrypted credentials — see .env.example), never committed and never logged
  # (config/initializers/filter_parameter_logging.rb masks it). Transport and
  # HTTP errors map to GenerationError so the job degrades to a safe failure
  # instead of crashing (ADR-023 keeps inference out of controllers).
  class GeminiClient
    include Extraction::VisionDocumentContext

    DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com"
    DEFAULT_API_VERSION = "v1beta"
    DEFAULT_MODEL = "gemini-2.5-flash"
    DEFAULT_READ_TIMEOUT_SECONDS = 120
    PROVIDER = "google_gemini"

    # Raised for connection/protocol failures (mirrors OllamaClient::GenerationError)
    # so the adapter maps them to a safe failure instead of crashing the job.
    class GenerationError < StandardError; end
    # Raised when no API key is configured, so the client fails closed rather
    # than making a live call without credentials. It is a GenerationError so the
    # same safe-failure path handles it.
    class MissingApiKey < GenerationError; end

    # `transport` is an optional seam for tests: a callable invoked instead of a
    # live Net::HTTP request. It receives (uri:, headers:, body:, read_timeout:)
    # and must return [status_integer, response_body_string]; raising
    # Errno::ECONNREFUSED / SocketError / Timeout::Error from it is treated
    # exactly like the equivalent live failure.
    def initialize(api_key: self.class.default_api_key,
                   base_url: ENV.fetch("PARSY_GEMINI_URL", DEFAULT_BASE_URL),
                   model: ENV["PARSY_GEMINI_MODEL"],
                   api_version: ENV.fetch("PARSY_GEMINI_API_VERSION", DEFAULT_API_VERSION),
                   transport: nil,
                   open_timeout: 5,
                   read_timeout: nil)
      @api_key = api_key.to_s
      @base_url = base_url.to_s.chomp("/")
      @model_override = model.presence
      @api_version = api_version.to_s
      @transport = transport
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    # All Parsy config comes from ENV (no Rails encrypted credentials); loaded via
    # foreman under bin/dev, or dotenv-rails/shell export for console/runner/tests.
    def self.default_api_key
      ENV["GEMINI_API_KEY"].presence
    end

    def extract_invoice(request)
      request = stringify(request)
      raise MissingApiKey, "GEMINI_API_KEY is not configured" if api_key.empty?

      model = model_for(request)
      body = JSON.generate(request_body(request))
      started = monotonic_ms
      response = post_generate(model:, body:, read_timeout: read_timeout_for(request))
      latency_ms = monotonic_ms - started

      {
        json_text: response_text(response),
        metadata: response_metadata(response, model:, latency_ms:)
      }
    end
    alias_method :call, :extract_invoice

    private

    attr_reader :api_key, :base_url, :model_override, :api_version, :transport, :open_timeout, :read_timeout

    # An explicit ENV/init override wins, then the model the adapter asked for,
    # then the documented default.
    def model_for(request)
      model_override || request["model"].presence || DEFAULT_MODEL
    end

    def request_body(request)
      {
        contents: [ { role: "user", parts: content_parts(request) } ],
        generationConfig: generation_config(request)
      }
    end

    # The prompt text first, then each page image as inline data. compose_prompt
    # comes from Extraction::VisionDocumentContext (shared with OllamaClient).
    def content_parts(request)
      parts = [ { text: compose_prompt(request) } ]
      Array(request["images_bytes"]).each do |bytes|
        raw = bytes.to_s.b
        next if raw.empty?

        parts << { inline_data: { mime_type: image_mime_type(raw), data: Base64.strict_encode64(raw) } }
      end
      parts
    end

    # responseMimeType asks Gemini for a bare JSON object (no markdown fences),
    # which is exactly what Extraction::ProviderAdapter#parse_json expects.
    # temperature defaults to 0 for reproducibility, mirroring the local route.
    def generation_config(request)
      settings = request["deterministic_settings"] || {}
      {
        temperature: settings.fetch("temperature", 0),
        topP: settings.fetch("top_p", 1),
        responseMimeType: "application/json"
      }
    end

    # Returns the model's text unmodified (concatenated when Gemini splits the
    # answer across parts). "" when the response carries no candidate text — e.g.
    # a safety block — so the adapter reports JSON_INVALID and degrades safely.
    def response_text(payload)
      parts = payload.dig("candidates", 0, "content", "parts")
      return "" unless parts.is_a?(Array)

      parts.filter_map { |part| part["text"] if part.is_a?(Hash) }.join
    end

    # Content-free only: model/version, latency, token counts, finish/block
    # reasons. Never the candidate text, the prompt, or the API key.
    def response_metadata(payload, model:, latency_ms:)
      usage = payload["usageMetadata"] || {}
      {
        provider: PROVIDER,
        model: payload["modelVersion"] || model,
        model_version: payload["modelVersion"],
        latency_ms: latency_ms,
        input_tokens: usage["promptTokenCount"],
        output_tokens: usage["candidatesTokenCount"],
        finish_reason: payload.dig("candidates", 0, "finishReason"),
        block_reason: payload.dig("promptFeedback", "blockReason")
      }.compact
    end

    def post_generate(model:, body:, read_timeout:)
      uri = endpoint_uri(model)
      status, response_body = perform_request(uri:, headers: request_headers, body:, read_timeout:)
      unless (200..299).cover?(status.to_i)
        raise GenerationError, "gemini returned HTTP #{status}#{error_reason_suffix(response_body)}"
      end

      JSON.parse(response_body.to_s)
    rescue Errno::ECONNREFUSED, SocketError, IOError, SystemCallError => error
      raise GenerationError, "gemini unreachable: #{error.class}"
    end

    # Google error bodies carry a machine-readable enum (e.g. INVALID_ARGUMENT /
    # API_KEY_INVALID / RESOURCE_EXHAUSTED). Surfacing only that enum keeps the
    # exception diagnosable — a bad key vs a rate limit vs a bad request — without
    # logging free text or any document content.
    def error_reason_suffix(response_body)
      error = JSON.parse(response_body.to_s)["error"]
      return "" unless error.is_a?(Hash)

      reason = Array(error["details"]).filter_map { |d| d["reason"] if d.is_a?(Hash) }.first || error["status"]
      reason ? " (#{reason})" : ""
    rescue JSON::ParserError
      ""
    end

    def perform_request(uri:, headers:, body:, read_timeout:)
      return transport.call(uri:, headers:, body:, read_timeout:) if transport

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http.use_ssl = (uri.scheme == "https")

      post = Net::HTTP::Post.new(uri)
      headers.each { |key, value| post[key] = value }
      post.body = body

      response = http.request(post)
      [ response.code.to_i, response.body.to_s ]
    end

    def endpoint_uri(model)
      URI.join("#{base_url}/", "#{api_version}/", "models/#{model}:generateContent")
    end

    # The key travels in the x-goog-api-key header, never the URL, so it does not
    # end up in access logs or the request line.
    def request_headers
      {
        "Content-Type" => "application/json",
        "x-goog-api-key" => api_key
      }
    end

    def read_timeout_for(request)
      return read_timeout if read_timeout

      timeout_ms = request["timeout_ms"]
      seconds = timeout_ms ? (Integer(timeout_ms) / 1000.0).ceil : 0
      [ seconds, DEFAULT_READ_TIMEOUT_SECONDS ].max
    end

    def image_mime_type(bytes)
      return "image/jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
      return "image/png" if bytes.start_with?("\x89PNG".b)
      return "image/webp" if bytes[0, 4] == "RIFF".b && bytes[8, 4] == "WEBP".b

      "image/png"
    end

    def monotonic_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
    end

    def stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), out| out[key.to_s] = stringify(item) }
      when Array then value.map { |item| stringify(item) }
      else value
      end
    end
  end
end
