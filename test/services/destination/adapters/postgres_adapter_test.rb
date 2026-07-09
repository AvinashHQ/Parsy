# frozen_string_literal: true

require "test_helper"

module Destination
  module Adapters
    # Integration coverage against the live test PostgreSQL server: the adapter
    # opens its own connection outside Active Record, so scratch tables are
    # created and dropped through the adapter itself.
    class PostgresAdapterTest < ActiveSupport::TestCase
      setup do
        @table = "dest_target_#{SecureRandom.hex(4)}"
      end

      teardown do
        adapter.open { |session| session.exec(%(DROP TABLE IF EXISTS "#{@table}")) }
      end

      test "executes parameterized queries and quotes identifiers" do
        rows = adapter.open do |session|
          assert_equal %("weird""name"), session.quote_identifier(%(weird"name))
          session.exec("SELECT ?::integer AS answer, ? AS label", [ 42, "it's safe" ])
        end

        assert_equal [ { "answer" => "42", "label" => "it's safe" } ], rows
      end

      test "wraps query failures without leaking driver detail" do
        error = assert_raises(QueryFailed) do
          adapter.open { |session| session.exec("SELECT * FROM missing_table_#{SecureRandom.hex(4)}") }
        end

        assert_match(/destination query failed/, error.message)
      end

      test "wraps unreachable hosts as content-free connection failures" do
        unreachable = Postgres.new(
          host: "127.0.0.1", port: 1, database: "nope", username: "nobody", password: "secret-value", ssl_mode: "disable"
        )

        error = assert_raises(ConnectionFailed) do
          unreachable.open { |session| session.exec("SELECT 1") }
        end

        assert_match(/destination connection failed/, error.message)
        assert_no_match(/secret-value|nobody/, error.message)
      end

      test "introspects a vendor-style table end-to-end through the schema introspector" do
        adapter.open do |session|
          session.exec(<<~SQL)
            CREATE TABLE "#{@table}" (
              inv_no varchar(64) NOT NULL UNIQUE,
              grand_total numeric(12, 2),
              issued_on date,
              note text
            )
          SQL
        end

        connection = create_connection!
        snapshot = SchemaIntrospector.call(connection: connection, adapter: adapter)

        table = snapshot["tables"].find { |candidate| candidate["name"] == @table }
        assert_not_nil table, "scratch table missing from snapshot"

        inv_no = table["columns"].find { |column| column["name"] == "inv_no" }
        assert_equal "character varying", inv_no["data_type"]
        assert_not inv_no["nullable"]
        assert inv_no["unique"]
        assert_not inv_no["primary_key"]

        grand_total = table["columns"].find { |column| column["name"] == "grand_total" }
        assert_equal "numeric", grand_total["data_type"]
        assert grand_total["nullable"]

        assert_predicate connection.reload, :schema_known?
      end

      test "connection tester passes against the live database" do
        result = ConnectionTester.call(connection: nil, adapter: adapter)

        assert_predicate result, :success?
        assert_operator result.latency_ms, :>, 0
      end

      private

      def adapter
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        Postgres.new(
          host: config[:host] || "localhost",
          port: config[:port] || 5432,
          database: config[:database],
          username: config[:username] || ENV["USER"],
          password: config[:password].to_s,
          ssl_mode: "prefer"
        )
      end

      def create_connection!
        tenant = Tenant.create!(name: "PG Tenant", slug: "dest-pg-#{SecureRandom.hex(3)}", hosting_region: "local", storage_region: "local")
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        Destination::DatabaseConnection.create!(
          tenant: tenant,
          label: "live-pg",
          adapter: "postgresql",
          host: config[:host] || "localhost",
          port: config[:port] || 5432,
          database_name: config[:database],
          username: config[:username] || ENV["USER"],
          password: config[:password].to_s,
          ssl_mode: "prefer"
        )
      end
    end
  end
end
