# frozen_string_literal: true

require "test_helper"

module RemoteVision
  # M4.5-02 (#83): the cloud vision provider must answer the same interface as
  # LocalExtraction::OllamaClient and drop into Extraction::ProviderAdapter
  # unchanged. Built and tested against a stubbed HTTP boundary because no live
  # GEMINI_API_KEY is provisioned yet (the live call is gated by the key + #84's
  # provider selection).
  class GeminiClientTest < ActiveSupport::TestCase
    CANONICAL_FIXTURE = Rails.root.join("test/fixtures/files/canonical/fix_001_minimal_visual_usd.json")
    PNG_BYTES = "\x89PNG\r\n\x1a\nrest".b
    JPEG_BYTES = "\xFF\xD8\xFF\xE0rest".b

    # Records every call and returns a canned [status, body] (or raises), so a
    # test can both drive the client and assert on the request it built.
    class StubTransport
      attr_reader :calls

      def initialize(status: 200, body: "{}", error: nil)
        @status = status
        @body = body
        @error = error
        @calls = []
      end

      def call(uri:, headers:, body:, read_timeout:)
        @calls << { uri:, headers:, body:, read_timeout: }
        raise @error if @error

        [ @status, @body ]
      end
    end

    test "builds a Gemini generateContent request with prompt text, image, and JSON output" do
      transport = StubTransport.new(body: gemini_envelope(valid_json))
      client = GeminiClient.new(api_key: "secret-key", model: "gemini-2.5-flash", transport:)

      client.extract_invoice(
        "prompt" => "SHARED PROMPT with line_net_amount",
        "document" => { "family" => "visual_pdf", "route" => "visual_model" },
        "parser_output" => { "text" => "digital text" },
        "images_bytes" => [ PNG_BYTES ]
      )

      call = transport.calls.sole
      assert_equal "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", call[:uri].to_s
      assert_equal "secret-key", call[:headers]["x-goog-api-key"]
      assert_equal "application/json", call[:headers]["Content-Type"]

      body = JSON.parse(call[:body])
      parts = body.dig("contents", 0, "parts")
      assert_equal "SHARED PROMPT with line_net_amount", parts.first["text"].lines.first.strip
      assert_includes parts.first["text"], "digital text"
      assert_equal "image/png", parts.last.dig("inline_data", "mime_type")
      assert_equal Base64.strict_encode64(PNG_BYTES), parts.last.dig("inline_data", "data")
      assert_equal "application/json", body.dig("generationConfig", "responseMimeType")
      assert_equal 0, body.dig("generationConfig", "temperature")
    end

    test "keeps the API key out of the URL so it cannot leak into request logs" do
      transport = StubTransport.new(body: gemini_envelope(valid_json))
      client = GeminiClient.new(api_key: "secret-key", transport:)

      client.extract_invoice("prompt" => "p")

      refute_includes transport.calls.sole[:uri].to_s, "secret-key"
    end

    test "returns the model's JSON text unmodified with content-free metadata" do
      transport = StubTransport.new(body: gemini_envelope(valid_json, prompt_tokens: 321, candidate_tokens: 654))
      client = GeminiClient.new(api_key: "secret-key", transport:)

      result = client.extract_invoice("prompt" => "p")

      assert_equal valid_json, result[:json_text]
      metadata = result[:metadata]
      assert_equal "google_gemini", metadata[:provider]
      assert_equal "gemini-2.5-flash-001", metadata[:model]
      assert_equal 321, metadata[:input_tokens]
      assert_equal 654, metadata[:output_tokens]
      assert_equal "STOP", metadata[:finish_reason]
      assert_kind_of Integer, metadata[:latency_ms]
    end

    test "metadata never carries the api key or the extracted invoice content" do
      transport = StubTransport.new(body: gemini_envelope(valid_json))
      client = GeminiClient.new(api_key: "secret-key", transport:)

      serialized = client.extract_invoice("prompt" => "p")[:metadata].to_s

      refute_includes serialized, "secret-key"
      refute_includes serialized, "Northstar" # supplier name in the canonical fixture
      refute_includes serialized, "INV-2026-1042" # invoice number in the canonical fixture
    end

    test "detects the image mime type from the raw bytes" do
      transport = StubTransport.new(body: gemini_envelope(valid_json))
      client = GeminiClient.new(api_key: "k", transport:)

      client.extract_invoice("prompt" => "p", "images_bytes" => [ JPEG_BYTES ])

      body = JSON.parse(transport.calls.sole[:body])
      assert_equal "image/jpeg", body.dig("contents", 0, "parts").last.dig("inline_data", "mime_type")
    end

    test "empty candidate text degrades to an empty string for the adapter" do
      transport = StubTransport.new(body: JSON.generate(promptFeedback: { blockReason: "SAFETY" }))
      client = GeminiClient.new(api_key: "k", transport:)

      result = client.extract_invoice("prompt" => "p")

      assert_equal "", result[:json_text]
      assert_equal "SAFETY", result[:metadata][:block_reason]
    end

    test "non-2xx responses map to GenerationError" do
      transport = StubTransport.new(status: 429, body: "rate limited")
      client = GeminiClient.new(api_key: "k", transport:)

      error = assert_raises(GeminiClient::GenerationError) { client.extract_invoice("prompt" => "p") }
      assert_includes error.message, "429"
    end

    test "a Google error body surfaces its reason enum in the GenerationError" do
      body = JSON.generate(error: { code: 400, status: "INVALID_ARGUMENT", details: [ { reason: "API_KEY_INVALID" } ] })
      transport = StubTransport.new(status: 400, body:)
      client = GeminiClient.new(api_key: "bad-key", transport:)

      error = assert_raises(GeminiClient::GenerationError) { client.extract_invoice("prompt" => "p") }
      assert_includes error.message, "API_KEY_INVALID"
      refute_includes error.message, "bad-key"
    end

    test "connection errors map to GenerationError so the job degrades safely" do
      transport = StubTransport.new(error: Errno::ECONNREFUSED.new)
      client = GeminiClient.new(api_key: "k", transport:)

      assert_raises(GeminiClient::GenerationError) { client.extract_invoice("prompt" => "p") }
    end

    test "timeouts propagate as Timeout::Error for the adapter's TIMEOUT mapping" do
      transport = StubTransport.new(error: Timeout::Error.new("slow"))
      client = GeminiClient.new(api_key: "k", transport:)

      assert_raises(Timeout::Error) { client.extract_invoice("prompt" => "p") }
    end

    test "a missing API key fails closed without any network call" do
      transport = StubTransport.new
      client = GeminiClient.new(api_key: "", transport:)

      assert_raises(GeminiClient::MissingApiKey) { client.extract_invoice("prompt" => "p") }
      assert_empty transport.calls
    end

    test "MissingApiKey is a GenerationError so the safe-failure path handles it" do
      assert_operator GeminiClient::MissingApiKey, :<, GeminiClient::GenerationError
    end

    test "default_api_key reads the key from ENV" do
      original = ENV["GEMINI_API_KEY"]
      ENV["GEMINI_API_KEY"] = "env-key"

      assert_equal "env-key", GeminiClient.default_api_key
    ensure
      ENV["GEMINI_API_KEY"] = original
    end

    test "drops into Extraction::ProviderAdapter which parses and validates unchanged" do
      transport = StubTransport.new(body: gemini_envelope(valid_json))
      client = GeminiClient.new(api_key: "k", transport:)

      result = Extraction::ProviderAdapter.new(provider: client).extract(
        source_sha256: "abc123",
        route: "visual_model",
        prompt_id: "extract_invoice_v2",
        model: "gemini-2.5-flash"
      )

      assert result.success?
      assert_instance_of Canonical::Invoice, result.candidate
      assert_equal "2.0", result.candidate.schema_version
      assert_empty Canonical::SchemaValidator.new.validate(result.attributes)
    end

    private

    def valid_json
      @valid_json ||= CANONICAL_FIXTURE.read
    end

    def gemini_envelope(json_text, finish_reason: "STOP", prompt_tokens: 100, candidate_tokens: 200)
      JSON.generate(
        candidates: [ { content: { role: "model", parts: [ { text: json_text } ] }, finishReason: finish_reason } ],
        usageMetadata: {
          promptTokenCount: prompt_tokens,
          candidatesTokenCount: candidate_tokens,
          totalTokenCount: prompt_tokens + candidate_tokens
        },
        modelVersion: "gemini-2.5-flash-001"
      )
    end
  end
end
