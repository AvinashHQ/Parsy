# frozen_string_literal: true

require "pg"

module Destination
  module Adapters
    class Postgres
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
          client.exec("SET statement_timeout = #{STATEMENT_TIMEOUT_MS}")
          yield Session.new(client)
        rescue PG::Error => error
          raise QueryFailed, "destination query failed (#{error.class.name.demodulize})"
        ensure
          client.close
        end
      end

      def default_schema
        "public"
      end

      class Session
        def initialize(client)
          @client = client
        end

        # Executes SQL with `?` placeholders bound server-side ($n). Returns an
        # array of string-keyed row hashes. `?` inside string literals is not
        # supported — callers keep literals out of adapter-bound SQL.
        def exec(sql, params = [])
          @client.exec_params(positional(sql), params).to_a
        rescue PG::Error => error
          raise QueryFailed, "destination query failed (#{error.class.name.demodulize})"
        end

        def quote_identifier(name)
          PG::Connection.quote_ident(name.to_s)
        end

        def transaction
          exec("BEGIN")
          result = yield
          exec("COMMIT")
          result
        rescue StandardError => error
          begin
            exec("ROLLBACK")
          rescue Adapters::Error
            nil
          end
          raise error
        end

        private

        def positional(sql)
          index = 0
          sql.gsub("?") { "$#{index += 1}" }
        end
      end

      private

      def connect
        PG.connect(
          host: @host,
          port: @port,
          dbname: @database,
          user: @username,
          password: @password,
          sslmode: @ssl_mode,
          connect_timeout: CONNECT_TIMEOUT_SECONDS
        )
      rescue PG::Error => error
        raise ConnectionFailed, "destination connection failed (#{error.class.name.demodulize})"
      end
    end
  end
end
