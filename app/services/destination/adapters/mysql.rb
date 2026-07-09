# frozen_string_literal: true

require "trilogy"

module Destination
  module Adapters
    class Mysql
      SSL_MODES = {
        "disable" => Trilogy::SSL_DISABLED,
        "prefer" => Trilogy::SSL_PREFERRED_NOVERIFY,
        "require" => Trilogy::SSL_REQUIRED_NOVERIFY
      }.freeze

      def initialize(host:, port:, database:, username:, password:, ssl_mode: "prefer")
        @host = host
        @port = port
        @database = database
        @username = username
        @password = password
        @ssl_mode = ssl_mode
      end

      def open
        client = connect
        begin
          client.query("SET SESSION max_execution_time = #{STATEMENT_TIMEOUT_MS}")
          yield Session.new(client)
        rescue Trilogy::Error => error
          raise wrap(error)
        ensure
          client.close
        end
      end

      def default_schema
        @database
      end

      class Session
        def initialize(client)
          @client = client
        end

        # Executes SQL with `?` placeholders. Trilogy has no server-side binds,
        # so values are client-side escaped, mirroring Rails' own MySQL quoting.
        def exec(sql, params = [])
          result = @client.query(bind(sql, params))
          fields = result.fields.map(&:to_s)
          result.rows.map { |row| fields.zip(row).to_h }
        rescue Trilogy::Error => error
          raise QueryFailed, "destination query failed (#{error.class.name.demodulize})"
        end

        def quote_identifier(name)
          "`#{name.to_s.gsub('`', '``')}`"
        end

        def bind(sql, params)
          remaining = params.dup
          bound = sql.gsub("?") do
            raise QueryFailed, "destination query failed (missing bind value)" if remaining.empty?

            literal(remaining.shift)
          end
          raise QueryFailed, "destination query failed (unused bind values)" unless remaining.empty?

          bound
        end

        private

        def literal(value)
          case value
          when nil then "NULL"
          when true then "1"
          when false then "0"
          when Integer, Float then value.to_s
          when BigDecimal then value.to_s("F")
          when Date then "'#{value.iso8601}'"
          when Time, DateTime then "'#{value.utc.strftime("%Y-%m-%d %H:%M:%S")}'"
          else "'#{@client.escape(value.to_s)}'"
          end
        end
      end

      private

      def connect
        Trilogy.new(
          host: @host,
          port: @port,
          username: @username,
          password: @password,
          database: @database,
          connect_timeout: CONNECT_TIMEOUT_SECONDS,
          read_timeout: STATEMENT_TIMEOUT_MS / 1000,
          write_timeout: STATEMENT_TIMEOUT_MS / 1000,
          ssl_mode: SSL_MODES.fetch(@ssl_mode, Trilogy::SSL_PREFERRED_NOVERIFY)
        )
      rescue Trilogy::Error => error
        raise ConnectionFailed, "destination connection failed (#{error.class.name.demodulize})"
      end

      def wrap(error)
        case error
        when Trilogy::BaseConnectionError, Trilogy::ConnectionError, Trilogy::TimeoutError, Trilogy::ConnectionClosed
          ConnectionFailed.new("destination connection failed (#{error.class.name.demodulize})")
        else
          QueryFailed.new("destination query failed (#{error.class.name.demodulize})")
        end
      end
    end
  end
end
