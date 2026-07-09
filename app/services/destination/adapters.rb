# frozen_string_literal: true

module Destination
  # Raw-driver adapters for operator-configured external delivery databases.
  # Deliberately outside Active Record connection handling so customer
  # databases never share pools, transactions, or schema cache with Parsy's own.
  #
  # Adapter error messages are fixed, content-free strings plus the driver
  # error class name; raw driver messages can embed hosts or usernames and are
  # never propagated.
  module Adapters
    Error = Class.new(StandardError)
    UnsupportedAdapter = Class.new(Error)
    ConnectionFailed = Class.new(Error)
    QueryFailed = Class.new(Error)

    CONNECT_TIMEOUT_SECONDS = 5
    STATEMENT_TIMEOUT_MS = 10_000

    def self.for(connection)
      config = {
        host: connection.host,
        port: connection.port,
        database: connection.database_name,
        username: connection.username,
        password: connection.password,
        ssl_mode: connection.ssl_mode
      }
      case connection.adapter
      when "postgresql" then Postgres.new(**config)
      when "mysql" then Mysql.new(**config)
      else
        raise UnsupportedAdapter, "unsupported destination adapter"
      end
    end
  end
end
