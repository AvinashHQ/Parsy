# frozen_string_literal: true

module DestinationsHelper
  MAPPING_ISSUE_TEMPLATES = {
    "schema_snapshot_missing_target_table" => ->(issue) { "Target table “#{issue["table"]}” is not in the captured schema — re-capture the schema or re-propose the mapping." },
    "unknown_source_column" => ->(issue) { "“#{issue["source_column"]}” is not a canonical column." },
    "duplicate_target_column" => ->(issue) { "Target column “#{issue["target_column"]}” is mapped more than once." },
    "missing_target_column" => ->(issue) { "Target column “#{issue["target_column"]}” does not exist in the target table." },
    "type_mismatch" => ->(issue) { "“#{issue["source_column"]}” (#{issue["source_kind"]}) cannot feed “#{issue["target_column"]}” (#{issue["data_type"]})." },
    "unmapped_required_source" => ->(issue) { "“#{issue["source_column"]}” must be mapped — it is the idempotent push key." },
    "unmapped_required_target" => ->(issue) { "Target column “#{issue["target_column"]}” is NOT NULL without a default and must be fed by the mapping." },
    "document_key_not_unique" => ->(issue) { "“#{issue["target_column"]}” has no unique constraint; add one so re-pushes can never duplicate rows." },
    "unknown_target_type" => ->(issue) { "“#{issue["target_column"]}” has type #{issue["data_type"]}, which Parsy cannot type-check; values are sent as text." }
  }.freeze

  def mapping_issue_text(issue)
    template = MAPPING_ISSUE_TEMPLATES[issue["code"]]
    template ? template.call(issue) : issue["code"].to_s.humanize
  end
end
