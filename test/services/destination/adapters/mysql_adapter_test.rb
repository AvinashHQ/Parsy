# frozen_string_literal: true

require "test_helper"

module Destination
  module Adapters
    # No MySQL server runs locally or in CI; connection-free logic (binding,
    # quoting, ssl mapping) is covered directly and the connect path is covered
    # via a fast connection-refused failure. Real-server coverage runs only
    # when PARSY_TEST_MYSQL_URL is provided.
    class MysqlAdapterTest < ActiveSupport::TestCase
      class EscapingClient
        def escape(value)
          value.gsub("'", "''").gsub("\\", "\\\\\\\\")
        end
      end

      def session
        Mysql::Session.new(EscapingClient.new)
      end

      test "ssl mode mapping covers every model ssl mode" do
        assert_equal Destination::DatabaseConnection::SSL_MODES.sort, Mysql::SSL_MODES.keys.sort
      end

      test "binds placeholders with client-side escaped literals" do
        sql = session.bind(
          "INSERT INTO t (a, b, c, d, e, f, g) VALUES (?, ?, ?, ?, ?, ?, ?)",
          [ "o'brien", 42, BigDecimal("12.50"), nil, true, false, Date.new(2026, 7, 10) ]
        )

        assert_equal "INSERT INTO t (a, b, c, d, e, f, g) VALUES ('o''brien', 42, 12.5, NULL, 1, 0, '2026-07-10')", sql
      end

      test "rejects mismatched bind values" do
        assert_raises(QueryFailed) { session.bind("SELECT ?", []) }
        assert_raises(QueryFailed) { session.bind("SELECT 1", [ 1 ]) }
      end

      test "quotes identifiers with backtick doubling" do
        assert_equal "`weird``name`", session.quote_identifier("weird`name")
      end

      test "wraps unreachable hosts as content-free connection failures" do
        unreachable = Mysql.new(
          host: "127.0.0.1", port: 1, database: "nope", username: "nobody", password: "secret-value", ssl_mode: "disable"
        )

        error = assert_raises(ConnectionFailed) do
          unreachable.open { |mysql_session| mysql_session.exec("SELECT 1") }
        end

        assert_match(/destination connection failed/, error.message)
        assert_no_match(/secret-value|nobody/, error.message)
      end

      test "executes against a real MySQL server when configured" do
        url = ENV["PARSY_TEST_MYSQL_URL"]
        skip "set PARSY_TEST_MYSQL_URL to run real-server MySQL coverage" if url.blank?

        uri = URI.parse(url)
        live = Mysql.new(
          host: uri.host, port: uri.port || 3306, database: uri.path.delete_prefix("/"),
          username: uri.user, password: uri.password.to_s, ssl_mode: "prefer"
        )

        rows = live.open { |mysql_session| mysql_session.exec("SELECT ? AS answer", [ 42 ]) }
        assert_equal [ { "answer" => 42 } ], rows
      end
    end
  end
end
