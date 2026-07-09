# frozen_string_literal: true

require "test_helper"

module Destination
  class SchemaIntrospectorTest < ActiveSupport::TestCase
    class FakeSession
      def initialize(tables:, columns:, keys:)
        @tables = tables
        @columns = columns
        @keys = keys
      end

      def exec(sql, _params = [])
        case sql
        when /table_constraints/ then @keys
        when /information_schema\.tables/ then @tables
        when /information_schema\.columns/ then @columns
        else
          raise ArgumentError, "unexpected SQL: #{sql}"
        end
      end
    end

    class FakeAdapter
      def initialize(session)
        @session = session
      end

      def open
        yield @session
      end

      def default_schema
        "public"
      end
    end

    test "builds and persists a snapshot with nullability and key flags" do
      connection = create_connection!
      session = FakeSession.new(
        tables: [ { "table_name" => "customer_invoices" }, { "table_name" => "customer_lines" } ],
        columns: [
          { "table_name" => "customer_invoices", "column_name" => "inv_no", "data_type" => "character varying", "is_nullable" => "NO", "column_default" => nil },
          { "table_name" => "customer_invoices", "column_name" => "grand_total", "data_type" => "numeric", "is_nullable" => "YES", "column_default" => "0" },
          { "table_name" => "customer_lines", "column_name" => "inv_no", "data_type" => "character varying", "is_nullable" => "NO", "column_default" => nil },
          { "table_name" => "customer_lines", "column_name" => "pos", "data_type" => "integer", "is_nullable" => "NO", "column_default" => nil }
        ],
        keys: [
          { "table_name" => "customer_invoices", "column_name" => "inv_no", "constraint_type" => "PRIMARY KEY", "constraint_name" => "customer_invoices_pkey" },
          # Multi-column unique constraint: neither member column is unique alone.
          { "table_name" => "customer_lines", "column_name" => "inv_no", "constraint_type" => "UNIQUE", "constraint_name" => "lines_unique" },
          { "table_name" => "customer_lines", "column_name" => "pos", "constraint_type" => "UNIQUE", "constraint_name" => "lines_unique" }
        ]
      )

      snapshot = SchemaIntrospector.call(connection: connection, adapter: FakeAdapter.new(session))

      table_names = snapshot["tables"].map { |table| table["name"] }
      assert_equal %w[customer_invoices customer_lines], table_names

      inv_no = column(snapshot, "customer_invoices", "inv_no")
      assert_equal "character varying", inv_no["data_type"]
      assert_not inv_no["nullable"]
      assert inv_no["primary_key"]
      assert inv_no["unique"]

      grand_total = column(snapshot, "customer_invoices", "grand_total")
      assert grand_total["nullable"]
      assert_equal "0", grand_total["default"]
      assert_not grand_total["unique"]

      line_inv_no = column(snapshot, "customer_lines", "inv_no")
      assert_not line_inv_no["unique"], "multi-column constraint member must not be unique alone"

      connection.reload
      assert_predicate connection, :schema_known?
      assert_equal snapshot, connection.schema_snapshot
      assert_not_nil connection.schema_captured_at
    end

    test "persists an empty snapshot when the destination has no tables" do
      connection = create_connection!
      session = FakeSession.new(tables: [], columns: [], keys: [])

      snapshot = SchemaIntrospector.call(connection: connection, adapter: FakeAdapter.new(session))

      assert_equal({ "tables" => [] }, snapshot)
      assert_not connection.reload.schema_known?
      assert_not_nil connection.schema_captured_at
    end

    private

    def column(snapshot, table_name, column_name)
      table = snapshot["tables"].find { |candidate| candidate["name"] == table_name }
      table["columns"].find { |candidate| candidate["name"] == column_name }
    end

    def create_connection!
      tenant = Tenant.create!(name: "Dest Tenant", slug: "dest-introspect", hosting_region: "local", storage_region: "local")
      Destination::DatabaseConnection.create!(
        tenant: tenant,
        label: "warehouse",
        adapter: "postgresql",
        host: "db.customer.example",
        port: 5432,
        database_name: "erp",
        username: "warehouse_writer",
        password: "s3cret-value",
        ssl_mode: "prefer"
      )
    end
  end
end
