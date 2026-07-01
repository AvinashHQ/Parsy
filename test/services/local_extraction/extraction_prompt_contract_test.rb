# frozen_string_literal: true

require "test_helper"

module LocalExtraction
  # Guards the M4.5-01 fix (issue #82): the shared extraction prompt must embed the
  # nested Canonical Invoice v2 field names plus one worked example, so the model stops
  # guessing plausible-but-wrong names (the 0% schema-valid root cause in
  # 24_MODEL_SELECTION_REPORT.md §8.6). Canonical::SchemaValidator stays the acceptance
  # authority (ADR-010); these tests assert the *teaching material* is correct.
  class ExtractionPromptContractTest < ActiveSupport::TestCase
    RETIRED_TOP_LEVEL_ONLY_HASH = "dd6d07c5278aa8884050f1240663fe63be99c781b8daa59751eedb3aedc3a5f2"

    test "worked example embedded in the prompt is itself schema-valid" do
      example = JSON.parse(QwenSemanticAdapter::WORKED_EXAMPLE)

      errors = Canonical::SchemaValidator.new.validate(example)

      assert_empty errors, "embedded worked example must validate: #{errors.map(&:data_pointer)}"
    end

    test "worked example constructs a Canonical::Invoice v2 candidate" do
      example = JSON.parse(QwenSemanticAdapter::WORKED_EXAMPLE)

      candidate = Canonical::Invoice.from_hash(example)

      assert_instance_of Canonical::Invoice, candidate
      assert_equal Canonical::Invoice::SCHEMA_VERSION, candidate.schema_version
    end

    test "prompt embeds the exact nested field names §8.6 said the model kept missing" do
      prompt = QwenSemanticAdapter::PROMPT

      # party names / identifiers (was: name, ein)
      assert_includes prompt, "display_name"
      assert_includes prompt, "legal_name"
      assert_includes prompt, "identifiers"
      # totals (was: amount_due, line_subtotal, tax_total)
      assert_includes prompt, "payable_amount"
      assert_includes prompt, "tax_exclusive_amount"
      assert_includes prompt, "total_tax_amount"
      # line items (was: unit, line_net)
      assert_includes prompt, "unit_code"
      assert_includes prompt, "line_net_amount"
      # payment (was: terms) and required-but-absent scalars
      assert_includes prompt, "terms_text"
      assert_includes prompt, "tax_point_date"
      assert_includes prompt, "applied_region_pack"
    end

    test "prompt keeps the model from re-inventing the wrong names and stray source keys" do
      prompt = QwenSemanticAdapter::PROMPT

      assert_includes prompt, "NOT unit"
      assert_includes prompt, "NOT line_net"
      assert_includes prompt, "NOT terms"
      assert_includes prompt, "NOT amount_due"
      # §8.6 showed invented /source/sha256 and /source/byte_size against additionalProperties:false
      assert_includes prompt, "NEVER add sha256 or byte_size"
      assert_includes prompt, "additionalProperties"
    end

    test "prompt retains the money and tax-rate formatting rules" do
      prompt = QwenSemanticAdapter::PROMPT

      assert_includes prompt, "no percent sign"
      assert_includes prompt, "USD 387.54"
    end

    test "prompt hash is derived from the current prompt and no longer the retired top-level-only hash" do
      assert_equal Digest::SHA256.hexdigest(QwenSemanticAdapter::PROMPT), QwenSemanticAdapter::PROMPT_SHA256
      refute_equal RETIRED_TOP_LEVEL_ONLY_HASH, QwenSemanticAdapter::PROMPT_SHA256
    end
  end
end
