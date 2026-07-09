# frozen_string_literal: true

class CreateDestinationDatabaseConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :destination_database_connections do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :label, null: false
      t.string :adapter, null: false
      t.string :host, null: false
      t.integer :port, null: false
      t.string :database_name, null: false
      # Credentials are Active Record encrypted; text leaves headroom for ciphertext.
      t.text :username, null: false
      t.text :password
      t.string :ssl_mode, null: false, default: "prefer"
      t.jsonb :schema_snapshot, null: false, default: {}
      t.datetime :schema_captured_at
      t.timestamps
      t.index [ :tenant_id, :label ], unique: true
    end
  end
end
