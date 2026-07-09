# frozen_string_literal: true

class CreateDestinationFieldMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :destination_field_mappings do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :database_connection, null: false,
                   foreign_key: { to_table: :destination_database_connections },
                   index: { name: "index_destination_field_mappings_on_connection" }
      t.string :source_table, null: false
      t.string :target_table, null: false
      t.jsonb :column_mappings, null: false, default: []
      t.string :status, null: false, default: "proposed"
      t.string :origin, null: false, default: "heuristic"
      t.timestamps
      t.index [ :database_connection_id, :source_table ], unique: true,
              name: "index_destination_field_mappings_on_connection_and_source"
    end
  end
end
