# frozen_string_literal: true

require "test_helper"

module Security
  class ContentFreeLoggingTest < ActiveSupport::TestCase
    CANARY = "ACME SECRET INV-999 IBAN-SECRET signed-url-token"

    test "parameter filter redacts invoice content canaries" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter(
        canonical_invoice: { invoice: { number: CANARY } },
        evidence: [ { text_snippet: CANARY } ],
        reason: CANARY,
        raw_response_body: CANARY,
        signed_url: "https://example.test/#{CANARY}",
        safe_id: "sha256-only"
      )

      serialized = filtered.inspect
      refute_includes serialized, CANARY
      assert_includes serialized, "[FILTERED]"
      assert_includes serialized, "sha256-only"
    end

    test "review jobs serialize record identifiers only" do
      job = Review::ProcessDocumentJob.new(123)
      serialized = job.serialize.inspect

      assert_includes serialized, "123"
      refute_includes serialized, CANARY
      refute_includes serialized, "canonical_invoice"
      refute_includes serialized, "evidence"
    end
  end
end
