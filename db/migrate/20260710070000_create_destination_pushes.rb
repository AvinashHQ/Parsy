# frozen_string_literal: true

class CreateDestinationPushes < ActiveRecord::Migration[8.1]
  def change
    create_table :destination_pushes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :review_batch, null: false, foreign_key: true
      t.references :database_connection, null: false,
                   foreign_key: { to_table: :destination_database_connections },
                   index: { name: "index_destination_pushes_on_connection" }
      t.string :actor, null: false
      t.string :status, null: false, default: "pending"
      t.string :failure_reason
      # Per review-document results: counts/codes only, never invoice content.
      t.jsonb :document_results, null: false, default: {}
      t.integer :pushed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.index [ :review_batch_id, :created_at ]
    end
  end
end
