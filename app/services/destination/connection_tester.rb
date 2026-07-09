# frozen_string_literal: true

module Destination
  class ConnectionTester
    Result = Struct.new(:success, :latency_ms, :error_code, :message, keyword_init: true) do
      def success?
        success
      end
    end

    def self.call(connection:, adapter: nil)
      new(connection:, adapter:).call
    end

    def initialize(connection:, adapter: nil)
      @adapter = adapter || Adapters.for(connection)
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @adapter.open { |session| session.exec("SELECT 1") }
      Result.new(success: true, latency_ms: elapsed_ms(started), error_code: nil, message: "connection succeeded")
    rescue Adapters::ConnectionFailed => error
      Result.new(success: false, latency_ms: elapsed_ms(started), error_code: "connection_failed", message: error.message)
    rescue Adapters::QueryFailed => error
      Result.new(success: false, latency_ms: elapsed_ms(started), error_code: "query_failed", message: error.message)
    rescue Adapters::Error => error
      Result.new(success: false, latency_ms: elapsed_ms(started), error_code: "error", message: error.message)
    end

    private

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
    end
  end
end
