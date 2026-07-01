# frozen_string_literal: true

require "test_helper"

module Extraction
  # The prompt/text composition shared by the local and cloud vision clients.
  class VisionDocumentContextTest < ActiveSupport::TestCase
    class Host
      include Extraction::VisionDocumentContext
    end

    def setup
      @host = Host.new
    end

    test "extracted_text merges parser and ocr text and dedupes" do
      request = {
        "parser_output" => { "text" => "digital layer text" },
        "ocr_output" => { "pages" => [ { "text" => "ocr page text", "layout" => [ { "text" => "ocr block text" } ] } ] }
      }

      text = @host.send(:extracted_text, request)

      assert_includes text, "digital layer text"
      assert_includes text, "ocr page text"
      assert_includes text, "ocr block text"
    end

    test "extracted_text is byte-bounded" do
      request = { "parser_output" => { "text" => "x" * 40_000 } }

      text = @host.send(:extracted_text, request)

      assert_operator text.bytesize, :<=, Extraction::VisionDocumentContext::MAX_TEXT_BYTES
    end

    test "compose_prompt keeps the shared field contract and appends context + text" do
      request = {
        "prompt" => LocalExtraction::QwenSemanticAdapter::PROMPT,
        "document" => { "family" => "visual_pdf", "route" => "visual_model", "page_count" => 1 },
        "parser_output" => { "text" => "digital layer text" }
      }

      composed = @host.send(:compose_prompt, request)

      assert_includes composed, "line_net_amount"
      assert_includes composed, "Worked example"
      assert_includes composed, "never add sha256 or byte_size"
      assert_includes composed, "digital layer text"
      assert_includes composed, "\"route\": \"visual_model\""
    end

    test "compose_prompt notes an attached image only when images are present" do
      with_image = @host.send(:compose_prompt, { "prompt" => "base", "images_bytes" => [ "bytes" ] })
      without_image = @host.send(:compose_prompt, { "prompt" => "base", "images_bytes" => [] })

      assert_includes with_image, "page image is attached"
      refute_includes without_image, "page image is attached"
    end

    test "helper methods are private so they do not widen a client's public surface" do
      refute_respond_to @host, :compose_prompt
      refute_respond_to @host, :extracted_text
    end
  end
end
