# frozen_string_literal: true

module Canonical
  class DuplicateDetector
    Match = Data.define(:existing_document_id, :fingerprint)

    def self.call(candidate:, tenant_id:, existing_fingerprints: {})
      new(candidate: candidate, tenant_id: tenant_id, existing_fingerprints: existing_fingerprints).call
    end

    def initialize(candidate:, tenant_id:, existing_fingerprints: {})
      @candidate = candidate
      @tenant_id = tenant_id
      @existing_fingerprints = existing_fingerprints
    end

    def call
      candidate_fingerprint = DuplicateFingerprint.call(invoice: candidate, tenant_id: tenant_id)
      matches = existing_fingerprints.filter_map do |document_id, fingerprint|
        Match.new(existing_document_id: document_id, fingerprint: fingerprint) if fingerprint == candidate_fingerprint.fingerprint
      end

      return [] if matches.empty?

      [ Finding.new(
        code: "PROBABLE_DUPLICATE",
        severity: "CRITICAL",
        behavior: "require_confirmation",
        field_paths: %w[/supplier /invoice/number /invoice/issue_date /invoice/currency /totals/payable_amount],
        message: "Probable duplicate requires operator confirmation",
        metadata: { matches: matches.map(&:to_h), fingerprint_complete: candidate_fingerprint.complete? }
      ) ]
    end

    private

    attr_reader :candidate, :tenant_id, :existing_fingerprints
  end
end
