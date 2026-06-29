# frozen_string_literal: true

require "digest"

module Review
  class CandidateRevision < ApplicationRecord
    self.table_name = "candidate_revisions"

    STATUSES = %w[candidate approved rejected superseded].freeze

    belongs_to :document, class_name: "Review::Document", foreign_key: :review_document_id, inverse_of: :candidate_revisions
    has_many :findings, class_name: "Review::ValidationFinding", foreign_key: :candidate_revision_id, inverse_of: :candidate_revision, dependent: :destroy
    has_many :evidence_references, class_name: "Review::EvidenceReference", foreign_key: :candidate_revision_id, inverse_of: :candidate_revision, dependent: :destroy
    has_many :events, class_name: "Review::Event", foreign_key: :candidate_revision_id, inverse_of: :candidate_revision, dependent: :nullify

    validates :revision_number, presence: true, uniqueness: { scope: :review_document_id }
    validates :status, inclusion: { in: STATUSES }
    validates :canonical_invoice, presence: true
    validate :canonical_invoice_matches_schema

    before_update :prevent_approved_mutation
    before_save :record_immutable_digest, if: :approved?

    def invoice
      Canonical::Invoice.from_hash(canonical_invoice)
    end

    def approved?
      status == "approved"
    end

    def approval_ready?
      Review::AcceptancePolicy.new(self).auto_acceptable?
    end

    def unresolved_blocking_findings
      findings.unresolved.blocking
    end

    def evidence_for?(field_path)
      evidence_references.where(field_path: field_path).exists?
    end

    def operator_confirmed?(field_path)
      evidence_references.where(field_path: field_path, operator_confirmed: true).exists?
    end

    def high_risk_changed_paths_without_evidence_or_confirmation
      changed_field_paths & Review::AcceptancePolicy::HIGH_RISK_FIELD_PATHS.reject { |path| evidence_for?(path) || operator_confirmed?(path) }
    end

    private

    def canonical_invoice_matches_schema
      errors = Canonical::SchemaValidator.new.validate(canonical_invoice)
      return if errors.empty?

      errors.first(5).each { |error| self.errors.add(:canonical_invoice, "#{error.data_pointer.presence || '/'} #{error.type}") }
    end

    def prevent_approved_mutation
      return unless status_in_database == "approved"

      mutable = %w[updated_at]
      changed_immutable = changed.reject { |attribute| mutable.include?(attribute) }
      raise ActiveRecord::ReadOnlyRecord, "approved revisions are immutable" if changed_immutable.any?
    end

    def record_immutable_digest
      self.immutable_digest ||= Digest::SHA256.hexdigest(JSON.generate(sort_for_digest(canonical_invoice)))
    end

    def sort_for_digest(value)
      case value
      when Hash
        value.keys.sort.to_h { |key| [ key, sort_for_digest(value[key]) ] }
      when Array
        value.map { |entry| sort_for_digest(entry) }
      else
        value
      end
    end
  end
end
