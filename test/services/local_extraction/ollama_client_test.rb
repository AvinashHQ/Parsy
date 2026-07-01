# frozen_string_literal: true

require "test_helper"

module LocalExtraction
  class OllamaClientTest < ActiveSupport::TestCase
    test "extracts a bare JSON object unchanged" do
      assert_equal '{"number":"INV-1"}', OllamaClient.extract_json('{"number":"INV-1"}')
    end

    test "strips markdown code fences" do
      assert_equal '{"a":1}', OllamaClient.extract_json("```json\n{\"a\":1}\n```")
    end

    test "slices a JSON object out of surrounding reasoning prose" do
      text = "Here is the result:\n{\n  \"a\": 1\n}\nThat is my answer."
      assert_equal "{\n  \"a\": 1\n}", OllamaClient.extract_json(text)
    end

    test "returns empty string when no JSON span is present" do
      assert_equal "", OllamaClient.extract_json("I could not read the document.")
      assert_equal "", OllamaClient.extract_json(nil)
    end

    test "extracted_text merges parser_output and ocr_output text" do
      client = OllamaClient.new
      request = {
        "parser_output" => { "text" => "digital layer text" },
        "ocr_output" => { "pages" => [ { "text" => "ocr page text", "layout" => [ { "text" => "ocr block text" } ] } ] }
      }

      text = client.send(:extracted_text, request)

      assert_includes text, "digital layer text"
      assert_includes text, "ocr page text"
      assert_includes text, "ocr block text"
    end

    test "compose_prompt notes an attached image only when images_bytes is present" do
      client = OllamaClient.new
      with_image = client.send(:compose_prompt, { "prompt" => "base", "images_bytes" => [ "bytes" ] })
      without_image = client.send(:compose_prompt, { "prompt" => "base", "images_bytes" => [] })

      assert_includes with_image, "page image is attached"
      refute_includes without_image, "page image is attached"
    end

    test "encode_images base64-encodes raw image bytes and drops blanks" do
      client = OllamaClient.new
      images = client.send(:encode_images, { "images_bytes" => [ "\x89PNG".b, "", nil ] })

      assert_equal [ Base64.strict_encode64("\x89PNG".b) ], images
    end
  end
end
