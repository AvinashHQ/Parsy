# frozen_string_literal: true

require "test_helper"

module RemoteVision
  # Live integration test: exercises the REAL Gemini API end to end (no stubbed
  # transport), driving a real invoice image through the shared prompt and
  # Extraction::ProviderAdapter. Opt-in only — it is skipped unless BOTH
  # GEMINI_LIVE_TEST and GEMINI_API_KEY are set, so `bin/rails test` stays
  # hermetic, offline-safe, and free of API spend by default.
  #
  #   GEMINI_LIVE_TEST=1 GEMINI_API_KEY=... bin/rails test \
  #     test/services/remote_vision/gemini_client_live_test.rb
  class GeminiClientLiveTest < ActiveSupport::TestCase
    IMAGE_FIXTURE = Rails.root.join(
      "test/fixtures/files/invoice_parser/samples/synthetic_corpus/documents/images/IMG-004_receipt.png"
    )

    setup do
      skip "set GEMINI_LIVE_TEST=1 to run the live Gemini integration test" if ENV["GEMINI_LIVE_TEST"].to_s.empty?
      skip "GEMINI_API_KEY is not set" if ENV["GEMINI_API_KEY"].to_s.empty?
    end

    test "reads a real invoice image into canonical JSON the schema validator can consume" do
      client = GeminiClient.new
      request = {
        "prompt" => LocalExtraction::QwenSemanticAdapter::PROMPT,
        "document" => { "family" => "image", "route" => "visual_model", "page_count" => 1 },
        "images_bytes" => [ IMAGE_FIXTURE.binread ],
        "deterministic_settings" => { "temperature" => 0 }
      }

      response = client.extract_invoice(request)

      # Real round-trip + content-free metadata.
      assert_equal "google_gemini", response[:metadata][:provider]
      assert response[:metadata][:model].present?
      assert_kind_of Integer, response[:metadata][:latency_ms]
      refute_includes response[:metadata].to_s, ENV["GEMINI_API_KEY"]

      # The model returned parseable JSON — exactly what Extraction::ProviderAdapter
      # then validates (proven with a stub in gemini_client_test.rb). Schema
      # validity varies with the live model, so it is surfaced, not asserted.
      parsed = JSON.parse(response[:json_text])
      assert_kind_of Hash, parsed

      errors = Canonical::SchemaValidator.new.validate(parsed)
      puts "\n[live] schema_valid=#{errors.empty?} errors=#{errors.map(&:type).uniq.sort.join(',')} " \
           "latency=#{response[:metadata][:latency_ms]}ms tokens=#{response[:metadata][:input_tokens]}/#{response[:metadata][:output_tokens]}"
    end
  end
end
