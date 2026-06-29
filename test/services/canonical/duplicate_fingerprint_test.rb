# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class DuplicateFingerprintTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_formatting_differences_normalize_to_same_tenant_scoped_fingerprint
      first = invoice("fix_010_duplicate_a.json")
      second = invoice("fix_010_duplicate_b.json")

      first_fingerprint = Canonical::DuplicateFingerprint.call(invoice: first, tenant_id: "tenant-a")
      second_fingerprint = Canonical::DuplicateFingerprint.call(invoice: second, tenant_id: "tenant-a")

      assert_predicate first_fingerprint, :complete?
      assert_equal first_fingerprint.fingerprint, second_fingerprint.fingerprint
      assert_equal "vat:gb:gb123456789", first_fingerprint.parts.fetch(:supplier_key)
      assert_equal "inv20261042", second_fingerprint.parts.fetch(:invoice_number_key)
      assert_equal "120000", second_fingerprint.parts.fetch(:payable_minor_units)
    end

    def test_fingerprint_is_tenant_scoped
      invoice = invoice("fix_010_duplicate_a.json")

      first = Canonical::DuplicateFingerprint.call(invoice: invoice, tenant_id: "tenant-a")
      second = Canonical::DuplicateFingerprint.call(invoice: invoice, tenant_id: "tenant-b")

      refute_equal first.fingerprint, second.fingerprint
    end

    def test_similar_non_duplicate_has_distinct_fingerprint
      duplicate = Canonical::DuplicateFingerprint.call(invoice: invoice("fix_010_duplicate_a.json"), tenant_id: "tenant-a")
      similar = Canonical::DuplicateFingerprint.call(invoice: invoice("fix_011_non_duplicate_similar.json"), tenant_id: "tenant-a")

      refute_equal duplicate.fingerprint, similar.fingerprint
    end

    def test_probable_duplicate_returns_review_confirmation_finding
      existing = Canonical::DuplicateFingerprint.call(invoice: invoice("fix_010_duplicate_a.json"), tenant_id: "tenant-a")
      candidate = invoice("fix_010_duplicate_b.json")

      findings = Canonical::DuplicateDetector.call(
        candidate: candidate,
        tenant_id: "tenant-a",
        existing_fingerprints: { "existing-doc" => existing.fingerprint }
      )

      assert_equal [ "PROBABLE_DUPLICATE" ], findings.map(&:code)
      assert_equal "CRITICAL", findings.first.severity
      assert_equal "require_confirmation", findings.first.behavior
      assert_equal "existing-doc", findings.first.metadata.fetch(:matches).first.fetch(:existing_document_id)
    end

    private

    def invoice(filename)
      Canonical::Invoice.from_json(FIXTURE_DIR.join(filename).read)
    end
  end
end
