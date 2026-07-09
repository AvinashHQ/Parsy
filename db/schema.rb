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

ActiveRecord::Schema[8.1].define(version: 2026_07_10_050000) do
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

  create_table "destination_database_connections", force: :cascade do |t|
    t.string "adapter", null: false
    t.datetime "created_at", null: false
    t.string "database_name", null: false
    t.string "host", null: false
    t.string "label", null: false
    t.text "password"
    t.integer "port", null: false
    t.datetime "schema_captured_at"
    t.jsonb "schema_snapshot", default: {}, null: false
    t.string "ssl_mode", default: "prefer", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.text "username", null: false
    t.index ["tenant_id", "label"], name: "index_destination_database_connections_on_tenant_id_and_label", unique: true
    t.index ["tenant_id"], name: "index_destination_database_connections_on_tenant_id"
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
    t.datetime "expires_at"
    t.string "format", null: false
    t.string "mapping_version", default: "generic_v1", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "purged_at"
    t.bigint "review_batch_id", null: false
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.index ["review_batch_id", "format"], name: "index_export_artifacts_on_review_batch_id_and_format"
    t.index ["review_batch_id"], name: "index_export_artifacts_on_review_batch_id"
  end

  create_table "purge_evidences", force: :cascade do |t|
    t.string "actor", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "object_counts", default: {}, null: false
    t.datetime "purged_at", null: false
    t.bigint "review_batch_id", null: false
    t.string "status", null: false
    t.bigint "tenant_id"
    t.datetime "updated_at", null: false
    t.index ["review_batch_id", "created_at"], name: "index_purge_evidences_on_review_batch_id_and_created_at"
    t.index ["review_batch_id"], name: "index_purge_evidences_on_review_batch_id"
    t.index ["tenant_id"], name: "index_purge_evidences_on_tenant_id"
  end

  create_table "review_batches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "purge_status", default: "active", null: false
    t.datetime "purged_at"
    t.datetime "retention_deadline_at"
    t.string "status", default: "uploaded", null: false
    t.bigint "tenant_id"
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_review_batches_on_tenant_id"
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
    t.datetime "purged_at"
    t.datetime "retention_deadline_at"
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

  create_table "tenants", force: :cascade do |t|
    t.string "allowed_processing_regions", default: [], null: false, array: true
    t.string "allowed_providers", default: [], null: false, array: true
    t.string "circuit_breaker_status", default: "closed", null: false
    t.datetime "created_at", null: false
    t.integer "current_spend_cents", default: 0, null: false
    t.string "hosting_region", default: "eu-west-2", null: false
    t.integer "monthly_spend_limit_cents", default: 1000, null: false
    t.string "name", null: false
    t.jsonb "privacy_approval", default: {}, null: false
    t.datetime "privacy_approved_at"
    t.string "privacy_approved_by"
    t.string "slug", null: false
    t.datetime "spend_period_started_at"
    t.string "storage_region", default: "eu-west-2", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
  end

  create_table "usage_spend_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "estimated_cents", default: 0, null: false
    t.string "idempotency_key"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", null: false
    t.string "status", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "created_at"], name: "index_usage_spend_events_on_tenant_id_and_created_at"
    t.index ["tenant_id", "idempotency_key"], name: "index_usage_spend_events_on_tenant_id_and_idempotency_key", unique: true
    t.index ["tenant_id"], name: "index_usage_spend_events_on_tenant_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_authenticated_at"
    t.string "name", null: false
    t.string "operator_token_digest", null: false
    t.string "role", default: "operator", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_token_digest"], name: "index_users_on_operator_token_digest", unique: true
    t.index ["tenant_id", "email"], name: "index_users_on_tenant_id_and_email", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
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
  add_foreign_key "destination_database_connections", "tenants"
  add_foreign_key "evidence_references", "candidate_revisions"
  add_foreign_key "evidence_references", "review_documents"
  add_foreign_key "export_artifacts", "review_batches"
  add_foreign_key "purge_evidences", "review_batches"
  add_foreign_key "purge_evidences", "tenants"
  add_foreign_key "review_batches", "tenants"
  add_foreign_key "review_documents", "candidate_revisions", column: "approved_revision_id"
  add_foreign_key "review_documents", "candidate_revisions", column: "current_revision_id"
  add_foreign_key "review_documents", "review_batches"
  add_foreign_key "review_events", "candidate_revisions"
  add_foreign_key "review_events", "review_batches"
  add_foreign_key "review_events", "review_documents"
  add_foreign_key "usage_spend_events", "tenants"
  add_foreign_key "users", "tenants"
  add_foreign_key "validation_findings", "candidate_revisions"
  add_foreign_key "validation_findings", "review_documents"
end
