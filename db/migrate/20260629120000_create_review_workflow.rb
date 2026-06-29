# frozen_string_literal: true

class CreateReviewWorkflow < ActiveRecord::Migration[8.1]
  def change
    create_table :review_batches do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "uploaded"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    create_table :review_documents do |t|
      t.references :review_batch, null: false, foreign_key: true
      t.string :status, null: false, default: "uploaded"
      t.string :source_sha256, null: false
      t.string :source_filename_digest
      t.string :source_format_family
      t.string :source_format_profile
      t.string :source_format_version
      t.string :detected_language
      t.string :detected_country
      t.string :detected_currency
      t.string :rule_pack_id, null: false, default: "global_generic_v1"
      t.string :rule_pack_version, null: false, default: "1.0.0"
      t.string :route
      t.string :capability_profile
      t.integer :risk_score, null: false, default: 0
      t.bigint :current_revision_id
      t.bigint :approved_revision_id
      t.jsonb :source_metadata, null: false, default: {}
      t.jsonb :processing_provenance, null: false, default: {}
      t.timestamps

      t.index [ :review_batch_id, :status ]
      t.index [ :review_batch_id, :risk_score ]
      t.index [ :source_sha256, :review_batch_id ], unique: true
    end

    create_table :candidate_revisions do |t|
      t.references :review_document, null: false, foreign_key: true
      t.integer :revision_number, null: false
      t.string :status, null: false, default: "candidate"
      t.jsonb :canonical_invoice, null: false, default: {}
      t.jsonb :source_metadata, null: false, default: {}
      t.jsonb :provenance, null: false, default: {}
      t.jsonb :locale_overrides, null: false, default: {}
      t.string :changed_field_paths, array: true, null: false, default: []
      t.string :approved_by
      t.datetime :approved_at
      t.string :immutable_digest
      t.timestamps

      t.index [ :review_document_id, :revision_number ], unique: true
      t.index [ :review_document_id, :status ]
    end

    create_table :validation_findings do |t|
      t.references :review_document, null: false, foreign_key: true
      t.references :candidate_revision, null: false, foreign_key: true
      t.string :code, null: false
      t.string :severity, null: false
      t.string :behavior
      t.string :field_paths, array: true, null: false, default: []
      t.text :message, null: false
      t.string :observed
      t.string :calculated
      t.string :tolerance
      t.string :pack_id
      t.string :pack_version
      t.string :resolution_state, null: false, default: "unresolved"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index [ :candidate_revision_id, :severity, :resolution_state ], name: "idx_findings_revision_severity_resolution"
      t.index [ :review_document_id, :resolution_state ]
    end

    create_table :evidence_references do |t|
      t.references :review_document, null: false, foreign_key: true
      t.references :candidate_revision, null: false, foreign_key: true
      t.string :field_path, null: false
      t.string :source_kind, null: false
      t.integer :page
      t.string :source_path
      t.string :text_snippet, limit: 500
      t.jsonb :bbox, null: false, default: {}
      t.boolean :operator_confirmed, null: false, default: false
      t.timestamps

      t.index [ :candidate_revision_id, :field_path ]
    end

    create_table :review_events do |t|
      t.references :review_batch, null: false, foreign_key: true
      t.references :review_document, null: false, foreign_key: true
      t.references :candidate_revision, foreign_key: true
      t.string :actor, null: false
      t.string :action, null: false
      t.string :changed_field_paths, array: true, null: false, default: []
      t.string :old_value_hash
      t.string :new_value_hash
      t.text :reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index [ :review_document_id, :action ]
      t.index [ :review_batch_id, :created_at ]
    end

    create_table :export_artifacts do |t|
      t.references :review_batch, null: false, foreign_key: true
      t.string :status, null: false, default: "created"
      t.string :format, null: false
      t.string :mapping_version, null: false, default: "generic_v1"
      t.jsonb :approved_revision_ids, null: false, default: []
      t.integer :byte_size, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index [ :review_batch_id, :format ]
    end

    add_foreign_key :review_documents, :candidate_revisions, column: :current_revision_id
    add_foreign_key :review_documents, :candidate_revisions, column: :approved_revision_id
  end
end
