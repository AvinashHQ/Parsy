# frozen_string_literal: true

require "test_helper"

module Destination
  class ConnectionTesterTest < ActiveSupport::TestCase
    class FakeSession
      def initialize(error: nil)
        @error = error
      end

      def exec(_sql, _params = [])
        raise @error if @error

        [ { "?column?" => 1 } ]
      end
    end

    class FakeAdapter
      def initialize(connect_error: nil, query_error: nil)
        @connect_error = connect_error
        @query_error = query_error
      end

      def open
        raise @connect_error if @connect_error

        yield FakeSession.new(error: @query_error)
      end
    end

    test "reports success with a latency measurement" do
      result = ConnectionTester.call(connection: nil, adapter: FakeAdapter.new)

      assert_predicate result, :success?
      assert_operator result.latency_ms, :>=, 0
      assert_nil result.error_code
      assert_equal "connection succeeded", result.message
    end

    test "maps connection failures to a content-free result" do
      adapter = FakeAdapter.new(connect_error: Adapters::ConnectionFailed.new("destination connection failed (ConnectionBad)"))

      result = ConnectionTester.call(connection: nil, adapter: adapter)

      assert_not result.success?
      assert_equal "connection_failed", result.error_code
      assert_no_match(/db\.customer|warehouse_writer|s3cret/, result.message)
    end

    test "maps query failures separately from connection failures" do
      adapter = FakeAdapter.new(query_error: Adapters::QueryFailed.new("destination query failed (UndefinedTable)"))

      result = ConnectionTester.call(connection: nil, adapter: adapter)

      assert_not result.success?
      assert_equal "query_failed", result.error_code
    end

    test "maps other adapter errors to a generic code" do
      adapter = FakeAdapter.new(connect_error: Adapters::UnsupportedAdapter.new("unsupported destination adapter"))

      result = ConnectionTester.call(connection: nil, adapter: adapter)

      assert_not result.success?
      assert_equal "error", result.error_code
    end

    test "adapter factory builds by adapter name and rejects unknown adapters" do
      connection = Destination::DatabaseConnection.new(
        adapter: "postgresql", host: "h", port: 5432, database_name: "d", username: "u", password: "p", ssl_mode: "prefer"
      )
      assert_instance_of Adapters::Postgres, Adapters.for(connection)

      connection.adapter = "mysql"
      assert_instance_of Adapters::Mysql, Adapters.for(connection)

      connection.adapter = "sqlserver"
      assert_raises(Adapters::UnsupportedAdapter) { Adapters.for(connection) }
    end
  end
end
