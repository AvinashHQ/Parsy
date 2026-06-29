# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_29_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "candidate_revisions", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.jsonb "canonical_invoice", default: {}, null: false
    t.string "changed_field_paths", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.string "immutable_digest"
    t.jsonb "locale_overrides", default: {}, null: false
    t.jsonb "provenance", default: {}, null: false
    t.bigint "review_document_id", null: false
    t.integer "revision_number", null: false
    t.jsonb "source_metadata", default: {}, null: false
    t.string "status", default: "candidate", null: false
    t.datetime "updated_at", null: false
    t.index ["review_document_id", "revision_number"], name: "idx_on_review_document_id_revision_number_46cdb9295a", unique: true
    t.index ["review_document_id", "status"], name: "index_candidate_revisions_on_review_document_id_and_status"
    t.index ["review_document_id"], name: "index_candidate_revisions_on_review_document_id"
  end

  create_table "evidence_references", force: :cascade do |t|
    t.jsonb "bbox", default: {}, null: false
    t.bigint "candidate_revision_id", null: false
    t.datetime "created_at", null: false
    t.string "field_path", null: false
    t.boolean "operator_confirmed", default: false, null: false
    t.integer "page"
    t.bigint "review_document_id", null: false
    t.string "source_kind", null: false
    t.string "source_path"
    t.string "text_snippet", limit: 500
    t.datetime "updated_at", null: false
    t.index ["candidate_revision_id", "field_path"], name: "idx_on_candidate_revision_id_field_path_2b5c04a286"
    t.index ["candidate_revision_id"], name: "index_evidence_references_on_candidate_revision_id"
    t.index ["review_document_id"], name: "index_evidence_references_on_review_document_id"
  end

  create_table "export_artifacts", force: :cascade do |t|
    t.jsonb "approved_revision_ids", default: [], null: false
    t.integer "byte_size", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "format", null: false
    t.string "mapping_version", default: "generic_v1", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "review_batch_id", null: false
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.index ["review_batch_id", "format"], name: "index_export_artifacts_on_review_batch_id_and_format"
    t.index ["review_batch_id"], name: "index_export_artifacts_on_review_batch_id"
  end

  create_table "review_batches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "status", default: "uploaded", null: false
    t.datetime "updated_at", null: false
  end

  create_table "review_documents", force: :cascade do |t|
    t.bigint "approved_revision_id"
    t.string "capability_profile"
    t.datetime "created_at", null: false
    t.bigint "current_revision_id"
    t.string "detected_country"
    t.string "detected_currency"
    t.string "detected_language"
    t.jsonb "processing_provenance", default: {}, null: false
    t.bigint "review_batch_id", null: false
    t.integer "risk_score", default: 0, null: false
    t.string "route"
    t.string "rule_pack_id", default: "global_generic_v1", null: false
    t.string "rule_pack_version", default: "1.0.0", null: false
    t.string "source_filename_digest"
    t.string "source_format_family"
    t.string "source_format_profile"
    t.string "source_format_version"
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_sha256", null: false
    t.string "status", default: "uploaded", null: false
    t.datetime "updated_at", null: false
    t.index ["review_batch_id", "risk_score"], name: "index_review_documents_on_review_batch_id_and_risk_score"
    t.index ["review_batch_id", "status"], name: "index_review_documents_on_review_batch_id_and_status"
    t.index ["review_batch_id"], name: "index_review_documents_on_review_batch_id"
    t.index ["source_sha256", "review_batch_id"], name: "index_review_documents_on_source_sha256_and_review_batch_id", unique: true
  end

  create_table "review_events", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor", null: false
    t.bigint "candidate_revision_id"
    t.string "changed_field_paths", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "new_value_hash"
    t.string "old_value_hash"
    t.text "reason"
    t.bigint "review_batch_id", null: false
    t.bigint "review_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_revision_id"], name: "index_review_events_on_candidate_revision_id"
    t.index ["review_batch_id", "created_at"], name: "index_review_events_on_review_batch_id_and_created_at"
    t.index ["review_batch_id"], name: "index_review_events_on_review_batch_id"
    t.index ["review_document_id", "action"], name: "index_review_events_on_review_document_id_and_action"
    t.index ["review_document_id"], name: "index_review_events_on_review_document_id"
  end

  create_table "validation_findings", force: :cascade do |t|
    t.string "behavior"
    t.string "calculated"
    t.bigint "candidate_revision_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "field_paths", default: [], null: false, array: true
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "observed"
    t.string "pack_id"
    t.string "pack_version"
    t.string "resolution_state", default: "unresolved", null: false
    t.bigint "review_document_id", null: false
    t.string "severity", null: false
    t.string "tolerance"
    t.datetime "updated_at", null: false
    t.index ["candidate_revision_id", "severity", "resolution_state"], name: "idx_findings_revision_severity_resolution"
    t.index ["candidate_revision_id"], name: "index_validation_findings_on_candidate_revision_id"
    t.index ["review_document_id", "resolution_state"], name: "idx_on_review_document_id_resolution_state_8b2ec57886"
    t.index ["review_document_id"], name: "index_validation_findings_on_review_document_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "candidate_revisions", "review_documents"
  add_foreign_key "evidence_references", "candidate_revisions"
  add_foreign_key "evidence_references", "review_documents"
  add_foreign_key "export_artifacts", "review_batches"
  add_foreign_key "review_documents", "candidate_revisions", column: "approved_revision_id"
  add_foreign_key "review_documents", "candidate_revisions", column: "current_revision_id"
  add_foreign_key "review_documents", "review_batches"
  add_foreign_key "review_events", "candidate_revisions"
  add_foreign_key "review_events", "review_batches"
  add_foreign_key "review_events", "review_documents"
  add_foreign_key "validation_findings", "candidate_revisions"
  add_foreign_key "validation_findings", "review_documents"
end
