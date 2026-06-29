# frozen_string_literal: true

require "digest"

module Review
  class RevisionEditor
    def self.call(revision:, patch:, overrides: {}, actor:, reason:)
      new(revision:, patch:, overrides:, actor:, reason:).call
    end

    def initialize(revision:, patch:, overrides:, actor:, reason:)
      @revision = revision
      @patch = patch.deep_stringify_keys
      @overrides = overrides.deep_stringify_keys.compact_blank
      @actor = actor
      @reason = reason
    end

    def call
      raise ActiveRecord::ReadOnlyRecord, "approved revisions are immutable" if revision.approved?

      ApplicationRecord.transaction do
        before = revision.canonical_invoice.deep_dup
        after = deep_merge(before.deep_dup, patch)
        changed_paths = changed_leaf_paths(before, after)

        next_revision = revision.document.candidate_revisions.create!(
          revision_number: revision.document.next_revision_number,
          canonical_invoice: after,
          source_metadata: revision.source_metadata,
          provenance: revision.provenance,
          locale_overrides: overrides,
          changed_field_paths: changed_paths
        )

        revision.evidence_references.find_each do |evidence|
          next_revision.evidence_references.create!(evidence.attributes.except("id", "candidate_revision_id", "created_at", "updated_at").merge(document: revision.document))
        end

        Canonical::UniversalEngine.new.validate(next_revision.invoice).each do |finding|
          Review::ValidationFinding.from_canonical!(next_revision, finding)
        end

        revision.update!(status: "superseded")
        revision.document.update!(current_revision: next_revision)
        revision.document.recompute_risk!
        revision.document.mark_review_state!
        revision.document.events.create!(
          batch: revision.document.batch,
          candidate_revision: next_revision,
          actor: actor,
          action: "revision_edited",
          changed_field_paths: changed_paths,
          old_value_hash: digest(before.slice(*top_level_keys(changed_paths))),
          new_value_hash: digest(after.slice(*top_level_keys(changed_paths))),
          reason: reason,
          metadata: { "overrides" => overrides }
        )

        next_revision
      end
    end

    private

    attr_reader :revision, :patch, :overrides, :actor, :reason

    def deep_merge(target, source)
      source.each do |key, value|
        target[key] = target[key].is_a?(Hash) && value.is_a?(Hash) ? deep_merge(target[key], value) : value
      end
      target
    end

    def changed_leaf_paths(before, after, prefix = "")
      keys = (before.keys + after.keys).uniq
      keys.flat_map do |key|
        path = "#{prefix}/#{key}"
        if before[key].is_a?(Hash) && after[key].is_a?(Hash)
          changed_leaf_paths(before[key], after[key], path)
        elsif before[key] == after[key]
          []
        else
          path
        end
      end
    end

    def top_level_keys(paths)
      paths.map { |path| path.split("/").second }.compact.uniq
    end

    def digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(payload))
    end
  end
end
