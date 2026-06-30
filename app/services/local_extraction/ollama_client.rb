# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module LocalExtraction
  # Boundary client that drives a local Ollama runtime to produce Canonical
  # Invoice v2 JSON. Responds to #extract_invoice (and #call) as expected by
  # LocalExtraction::QwenSemanticAdapter.
  #
  # The client is intentionally thin: it composes a prompt from the document
  # context plus any machine-readable text, asks Ollama for strict JSON, and
  # hands the raw text back to the adapter. The adapter owns JSON parsing,
  # schema validation, and provenance — this class never decides acceptance.
  class OllamaClient
    DEFAULT_BASE_URL = "http://localhost:11434"
    DEFAULT_MODEL = "qwen2.5-coder:1.5b"
    MAX_TEXT_BYTES = 12_000

    # Raised for connection/protocol failures so the caller can map them to a
    # safe failure instead of crashing the job.
    class GenerationError < StandardError; end

    def initialize(base_url: ENV.fetch("PARSY_OLLAMA_URL", DEFAULT_BASE_URL),
                   model: ENV["PARSY_OLLAMA_MODEL"],
                   open_timeout: 5,
                   read_timeout: nil)
      @base_url = base_url.to_s.chomp("/")
      @model_override = model.presence
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def extract_invoice(request)
      request = stringify(request)
      model = model_for(request)
      prompt = compose_prompt(request)
      options = generation_options(request)
      response = post_generate(model:, prompt:, options:, read_timeout: read_timeout_for(request))

      {
        json_text: self.class.extract_json(response_text(response)),
        metadata: {
          model: response["model"] || model,
          latency_ms: response["total_duration"] ? (response["total_duration"].to_i / 1_000_000) : nil,
          input_tokens: response["prompt_eval_count"],
          output_tokens: response["eval_count"],
          runtime: "ollama"
        }.compact
      }
    end
    alias_method :call, :extract_invoice

    # Pulls a single JSON object/array out of arbitrary model text: strips
    # markdown fences and any reasoning prose around the payload. Returns "" when
    # no JSON-looking span is present so the adapter reports JSON_INVALID.
    def self.extract_json(text)
      stripped = text.to_s.strip
      stripped = stripped.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "").strip
      open_index = stripped.index(/[\{\[]/)
      close_index = stripped.rindex(/[\}\]]/)
      return "" if open_index.nil? || close_index.nil? || close_index < open_index

      stripped[open_index..close_index]
    end

    private

    attr_reader :base_url, :model_override, :open_timeout, :read_timeout

    # Resolution order: an explicit ENV/init override wins (lets a host point at
    # whatever model it actually has pulled), then the model the adapter asked
    # for, then the documented default.
    def model_for(request)
      model_override || request["model"].presence || DEFAULT_MODEL
    end

    # Reasoning models (e.g. Qwen) emit grammar-constrained JSON into `thinking`
    # while leaving `response` empty; non-reasoning models use `response`.
    def response_text(payload)
      response = payload["response"].to_s
      response.strip.empty? ? payload["thinking"].to_s : response
    end

    def compose_prompt(request)
      base = request["prompt"].to_s
      document = request["document"] || {}
      text = extracted_text(request)

      <<~PROMPT
        #{base}

        Return a single JSON object that conforms to the Canonical Invoice v2 schema.
        Required top-level keys: schema_version ("#{Canonical::Invoice::SCHEMA_VERSION}"), document_id,
        document_type, source, locale, supplier, buyer, payee, invoice, references,
        allowances_charges, totals, tax_breakdowns, line_items, payment, evidence, uncertainties.
        Use null for any value you cannot read from the document. Do not invent values.
        Output JSON only — no prose, no markdown fences.

        Document metadata:
        #{JSON.pretty_generate(document)}

        Extracted document text:
        #{text.empty? ? '(no machine-readable text was available)' : text}
      PROMPT
    end

    def extracted_text(request)
      parser_output = request["parser_output"] || {}
      texts = []
      texts << parser_output["text"] if parser_output.is_a?(Hash)
      Array(parser_output.is_a?(Hash) ? parser_output["pages"] : nil).each do |page|
        texts << page["text"] if page.is_a?(Hash)
        Array(page.is_a?(Hash) ? page["layout"] : nil).each do |block|
          texts << block["text"] if block.is_a?(Hash)
        end
      end
      texts.compact.map(&:to_s).reject(&:empty?).uniq.join("\n").byteslice(0, MAX_TEXT_BYTES).to_s
    end

    def generation_options(request)
      settings = request["deterministic_settings"] || {}
      {
        temperature: settings.fetch("temperature", 0),
        top_p: settings.fetch("top_p", 1),
        top_k: settings.fetch("top_k", 1),
        seed: settings.fetch("seed", 0)
      }
    end

    def read_timeout_for(request)
      return read_timeout if read_timeout
      timeout_ms = request["timeout_ms"]
      seconds = timeout_ms ? (Integer(timeout_ms) / 1000.0).ceil : 0
      [ seconds, 120 ].max
    end

    def post_generate(model:, prompt:, options:, read_timeout:)
      uri = URI.join("#{base_url}/", "api/generate")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http.use_ssl = (uri.scheme == "https")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(model:, prompt:, stream: false, format: "json", options:)

      response = http.request(request)
      raise GenerationError, "ollama returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue Errno::ECONNREFUSED, SocketError, IOError, SystemCallError => error
      raise GenerationError, "ollama unreachable: #{error.class}"
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
