# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "base64"

module LocalExtraction
  # Boundary client that drives a local Ollama-hosted GLM-OCR model to turn
  # page image bytes into OCR text. Responds to #call (and #extract) as
  # expected by LocalExtraction::OcrEvidenceAdapter.
  #
  # PaddleOCR-VL-1.6 was the originally planned OCR model, but the only
  # Ollama-packaged build available (MedAIBase/PaddleOCR-VL) ships
  # without the vision projector and rejects image input outright ("image
  # input is not supported - hint: if this is unexpected, you may need to
  # provide the mmproj"). GLM-OCR is officially published on Ollama, MIT
  # licensed, and independently benchmarks at or above PaddleOCR-VL on
  # OmniDocBench, so it fills the same layout_ocr_evidence role until a
  # working PaddleOCR-VL runtime is available.
  class GlmOcrClient
    DEFAULT_BASE_URL = "http://localhost:11434"
    DEFAULT_MODEL = "glm-ocr"
    PROMPT = "OCR this document. Output the visible text in reading order, using " \
             "markdown tables for any tabular content. Do not summarize, translate, " \
             "or omit any visible text."

    class GenerationError < StandardError; end

    # A genuinely degraded (blurred/low-resolution) page measured ~265s on
    # this hardware, well above a clean page's ~10s; 300s leaves a small
    # margin above the worst case observed on the synthetic corpus.
    def initialize(base_url: ENV.fetch("PARSY_OLLAMA_URL", DEFAULT_BASE_URL),
                   model: ENV["PARSY_OLLAMA_OCR_MODEL"],
                   open_timeout: 5,
                   read_timeout: 300)
      @base_url = base_url.to_s.chomp("/")
      @model = model.presence || DEFAULT_MODEL
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call(bytes:, metadata: {}, options: {})
      image = bytes.to_s.b
      return { pages: [] } if image.empty?

      response = post_generate(image)
      text = response_text(response)

      {
        version: "glm-ocr-boundary-v1/#{response['model'] || model}",
        pages: [ { number: 1, text: text } ],
        metadata: {
          runtime: "ollama",
          model: response["model"] || model,
          latency_ms: response["total_duration"] ? (response["total_duration"].to_i / 1_000_000) : nil
        }.compact
      }
    rescue GenerationError
      { pages: [] }
    end
    alias_method :extract, :call

    private

    attr_reader :base_url, :model, :open_timeout, :read_timeout

    def response_text(payload)
      text = payload["response"].to_s
      text.strip.empty? ? payload["thinking"].to_s.strip : text.strip
    end

    def post_generate(image_bytes)
      uri = URI.join("#{base_url}/", "api/generate")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http.use_ssl = (uri.scheme == "https")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        model: model,
        prompt: PROMPT,
        images: [ Base64.strict_encode64(image_bytes) ],
        stream: false,
        options: { temperature: 0 }
      )

      response = http.request(request)
      raise GenerationError, "ollama returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue Errno::ECONNREFUSED, SocketError, IOError, SystemCallError => error
      raise GenerationError, "ollama unreachable: #{error.class}"
    end
  end
end
