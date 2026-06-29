# frozen_string_literal: true

require "digest"

module Review
  class ProviderResultIngester
    def self.call(batch:, source_sha256:, result:, source_metadata: {}, actor: "system")
      new(batch:, source_sha256:, result:, source_metadata:, actor:).call
    end

    def initialize(batch:, source_sha256:, result:, source_metadata:, actor:)
      @batch = batch
      @source_sha256 = source_sha256
      @result = result
      @source_metadata = source_metadata.deep_stringify_keys
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        document = batch.documents.find_or_initialize_by(source_sha256: source_sha256)
        return document if document.persisted? && terminal_review_state?(document)

        document.assign_attributes(document_attributes)
        document.save!

        if result.respond_to?(:success?) && result.success?
          persist_candidate!(document)
        else
          persist_failure!(document)
        end

        document.batch.refresh_status!
        document
      end
    end

    private

    attr_reader :batch, :source_sha256, :result, :source_metadata, :actor

    def document_attributes
      invoice_hash = candidate_hash
      source = invoice_hash.fetch("source", {})
      locale = invoice_hash.fetch("locale", {})
      details = invoice_hash.fetch("invoice", {})
      pack = locale.fetch("applied_region_pack", {}) || {}
      {
        status: "validating",
        source_filename_digest: digest(source_metadata["filename"].to_s),
        source_format_family: source["family"],
        source_format_profile: source["profile"],
        source_format_version: source["profile_version"],
        detected_language: locale["document_language"],
        detected_country: Array(locale["jurisdiction_candidates"]).first || locale["supplier_country"] || locale["buyer_country"],
        detected_currency: details["currency"],
        rule_pack_id: pack["id"].presence || "global_generic_v1",
        rule_pack_version: pack["version"].presence || "1.0.0",
        route: source["route"],
        capability_profile: provenance.fetch("capability", {}).fetch("level", nil),
        source_metadata: safe_source_metadata,
        processing_provenance: provenance
      }
    end

    def persist_candidate!(document)
      if (revision = idempotent_revision_for(document))
        document.update!(current_revision: revision) unless document.current_revision_id == revision.id
        document.recompute_risk!
        document.mark_review_state!
        record_event(document, revision, "candidate_reused")
        return revision
      end

      revision = document.candidate_revisions.create!(
        revision_number: document.next_revision_number,
        canonical_invoice: result.candidate.to_h,
        source_metadata: safe_source_metadata,
        provenance: provenance,
        changed_field_paths: []
      )

      result.candidate.evidence.each do |evidence|
        Review::EvidenceReference.from_canonical!(revision, evidence)
      end

      Canonical::UniversalEngine.new.validate(result.candidate).each do |finding|
        Review::ValidationFinding.from_canonical!(revision, finding)
      end

      document.update!(current_revision: revision)
      document.recompute_risk!
      document.mark_review_state!
      record_event(document, revision, "candidate_created")
    end

    def persist_failure!(document)
      document.update!(status: failure_status, processing_provenance: provenance)
      record_event(document, nil, failure_status)
    end

    def candidate_hash
      result.respond_to?(:candidate) && result.candidate ? result.candidate.to_h : {}
    end

    def provenance
      @provenance ||= begin
        attempt = result.respond_to?(:attempts) ? result.attempts.last : nil
        route_provenance = result.respond_to?(:provenance) && result.provenance ? result.provenance.deep_stringify_keys : {}
        route_provenance.merge({
          "idempotency_key" => result.respond_to?(:idempotency_key) ? result.idempotency_key : nil,
          "schema_version" => attempt&.schema_version || route_provenance["schema_version"] || Canonical::Invoice::SCHEMA_VERSION,
          "route" => attempt&.route || route_provenance["route"] || candidate_hash.dig("source", "route"),
          "profile_version" => attempt&.region || route_provenance["profile_version"] || "global_generic_v1",
          "provider" => attempt&.provider || route_provenance["provider"],
          "provider_version" => attempt&.provider_version || route_provenance["provider_version"],
          "model" => attempt&.model || route_provenance["model"],
          "model_version" => attempt&.model_version || route_provenance["model_version"] || route_provenance["model_revision"],
          "prompt_sha256" => attempt&.prompt_sha256 || route_provenance["prompt_sha256"],
          "latency_ms" => attempt&.latency_ms || route_provenance["latency_ms"],
          "repair_attempt" => attempt&.repair_attempt || route_provenance["repair_attempt"],
          "capability" => route_provenance["capability"] || { "id" => "global_generic_v1", "level" => "benchmarked" }
        }).compact
      end
    end

    def safe_source_metadata
      source_metadata.slice("page_count", "mime_type", "safe_preview_path", "route_profile_version")
    end

    def failure_status
      result.respond_to?(:error_code) && result.error_code.to_s.include?("UNSUPPORTED") ? "quarantined" : "failed"
    end

    def record_event(document, revision, action)
      document.events.create!(batch: batch, candidate_revision: revision, actor: actor, action: action, metadata: { "provenance_keys" => provenance.keys })
    end

    def terminal_review_state?(document)
      document.approved_revision_id.present? || document.status == "exported"
    end

    def idempotent_revision_for(document)
      idempotency_key = provenance["idempotency_key"].presence
      return nil if idempotency_key.blank?

      candidate_digest = digest_for_comparison(candidate_hash)
      document.candidate_revisions.detect do |revision|
        revision.provenance["idempotency_key"] == idempotency_key &&
          digest_for_comparison(revision.canonical_invoice) == candidate_digest
      end
    end

    def digest_for_comparison(value)
      Digest::SHA256.hexdigest(JSON.generate(sort_for_digest(value)))
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

    def digest(value)
      return nil if value.blank?

      Digest::SHA256.hexdigest(value)
    end
  end
end
