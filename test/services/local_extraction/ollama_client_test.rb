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
  end
end
