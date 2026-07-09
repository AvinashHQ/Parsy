# frozen_string_literal: true

module Destination
  # Reads the destination database's real table/column shape through
  # information_schema (portable across PostgreSQL and MySQL) and persists it
  # as the connection's schema snapshot for mapping proposal and validation.
  class SchemaIntrospector
    TABLES_SQL = <<~SQL
      SELECT table_name AS table_name
      FROM information_schema.tables
      WHERE table_schema = ? AND table_type = 'BASE TABLE'
      ORDER BY table_name
    SQL

    COLUMNS_SQL = <<~SQL
      SELECT table_name AS table_name, column_name AS column_name, data_type AS data_type,
             is_nullable AS is_nullable, column_default AS column_default
      FROM information_schema.columns
      WHERE table_schema = ?
      ORDER BY table_name, ordinal_position
    SQL

    KEY_COLUMNS_SQL = <<~SQL
      SELECT tc.table_name AS table_name, kcu.column_name AS column_name,
             tc.constraint_type AS constraint_type, tc.constraint_name AS constraint_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON kcu.constraint_name = tc.constraint_name
       AND kcu.table_schema = tc.table_schema
       AND kcu.table_name = tc.table_name
      WHERE tc.table_schema = ? AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
    SQL

    def self.call(connection:, adapter: nil)
      new(connection:, adapter:).call
    end

    def initialize(connection:, adapter: nil)
      @connection = connection
      @adapter = adapter || Adapters.for(connection)
    end

    def call
      snapshot = @adapter.open { |session| build_snapshot(session) }
      @connection.update!(schema_snapshot: snapshot, schema_captured_at: Time.current)
      snapshot
    end

    private

    def build_snapshot(session)
      schema = @adapter.default_schema
      tables = session.exec(TABLES_SQL, [ schema ])
      columns = session.exec(COLUMNS_SQL, [ schema ]).group_by { |row| row["table_name"] }
      keys = single_column_keys(session, schema)

      {
        "tables" => tables.map do |table_row|
          name = table_row["table_name"]
          {
            "name" => name,
            "columns" => Array(columns[name]).map { |column| column_entry(name, column, keys) }
          }
        end
      }
    end

    def column_entry(table_name, column, keys)
      primary_key = keys.fetch([ table_name, column["column_name"], "PRIMARY KEY" ], false)
      {
        "name" => column["column_name"],
        "data_type" => column["data_type"],
        "nullable" => column["is_nullable"].to_s.upcase == "YES",
        "default" => column["column_default"],
        "primary_key" => primary_key,
        "unique" => primary_key || keys.fetch([ table_name, column["column_name"], "UNIQUE" ], false)
      }
    end

    # Only single-column constraints mark a column unique: membership in a
    # multi-column key does not make the column unique on its own.
    def single_column_keys(session, schema)
      rows = session.exec(KEY_COLUMNS_SQL, [ schema ])
      grouped = rows.group_by { |row| [ row["table_name"], row["constraint_name"], row["constraint_type"] ] }
      grouped.each_with_object({}) do |((table, _constraint, type), members), result|
        next unless members.size == 1

        result[[ table, members.first["column_name"], type ]] = true
      end
    end
  end
end
