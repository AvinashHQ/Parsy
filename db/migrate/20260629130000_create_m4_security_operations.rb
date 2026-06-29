# frozen_string_literal: true

class CreateM4SecurityOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :hosting_region, null: false, default: "eu-west-2"
      t.string :storage_region, null: false, default: "eu-west-2"
      t.string :allowed_processing_regions, null: false, default: [], array: true
      t.string :allowed_providers, null: false, default: [], array: true
      t.integer :monthly_spend_limit_cents, null: false, default: 10_00
      t.integer :current_spend_cents, null: false, default: 0
      t.string :circuit_breaker_status, null: false, default: "closed"
      t.datetime :spend_period_started_at
      t.datetime :privacy_approved_at
      t.string :privacy_approved_by
      t.jsonb :privacy_approval, null: false, default: {}
      t.timestamps
      t.index :slug, unique: true
    end

    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :email, null: false
      t.string :name, null: false
      t.string :role, null: false, default: "operator"
      t.string :operator_token_digest, null: false
      t.datetime :last_authenticated_at
      t.timestamps
      t.index [ :tenant_id, :email ], unique: true
      t.index :operator_token_digest, unique: true
    end

    add_reference :review_batches, :tenant, foreign_key: true
    add_column :review_batches, :retention_deadline_at, :datetime
    add_column :review_batches, :purged_at, :datetime
    add_column :review_batches, :purge_status, :string, null: false, default: "active"

    add_column :review_documents, :retention_deadline_at, :datetime
    add_column :review_documents, :purged_at, :datetime

    add_column :export_artifacts, :expires_at, :datetime
    add_column :export_artifacts, :purged_at, :datetime

    create_table :purge_evidences do |t|
      t.references :tenant, foreign_key: true
      t.references :review_batch, null: false, foreign_key: true
      t.string :actor, null: false
      t.string :status, null: false
      t.jsonb :object_counts, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :purged_at, null: false
      t.timestamps
      t.index [ :review_batch_id, :created_at ]
    end

    create_table :usage_spend_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :provider, null: false
      t.integer :estimated_cents, null: false, default: 0
      t.string :status, null: false
      t.string :idempotency_key
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
      t.index [ :tenant_id, :created_at ]
      t.index [ :tenant_id, :idempotency_key ], unique: true
    end
  end
end
