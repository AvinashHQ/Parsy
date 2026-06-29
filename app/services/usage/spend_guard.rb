# frozen_string_literal: true

module Usage
  class SpendGuard
    COST_LIMIT_PAUSED = "COST_LIMIT_PAUSED"
    Result = Data.define(:allowed, :error_code, :remaining_cents)

    def self.reserve!(tenant:, provider:, estimated_cents:, idempotency_key: nil, metadata: {})
      new(tenant:).reserve!(provider:, estimated_cents:, idempotency_key:, metadata:)
    end

    def initialize(tenant:)
      @tenant = tenant
    end

    def reserve!(provider:, estimated_cents:, idempotency_key: nil, metadata: {})
      tenant.with_lock do
        if tenant.circuit_breaker_status == "open" || tenant.current_spend_cents + estimated_cents.to_i > tenant.monthly_spend_limit_cents
          tenant.update!(circuit_breaker_status: "open")
          record(provider:, estimated_cents:, idempotency_key:, status: "paused", metadata: metadata.merge(error_code: COST_LIMIT_PAUSED))
          return Result.new(allowed: false, error_code: COST_LIMIT_PAUSED, remaining_cents: remaining_cents)
        end

        tenant.increment!(:current_spend_cents, estimated_cents.to_i)
        record(provider:, estimated_cents:, idempotency_key:, status: "reserved", metadata: metadata.slice(:route, :region, :model))
        Result.new(allowed: true, error_code: nil, remaining_cents: remaining_cents)
      end
    end

    private

    attr_reader :tenant

    def remaining_cents
      [ tenant.monthly_spend_limit_cents - tenant.current_spend_cents, 0 ].max
    end

    def record(provider:, estimated_cents:, idempotency_key:, status:, metadata:)
      Usage::SpendEvent.create!(tenant:, provider:, estimated_cents: estimated_cents.to_i, idempotency_key:, status:, metadata: metadata.deep_stringify_keys)
    rescue ActiveRecord::RecordNotUnique
      # Idempotent retry; prior reservation/pause already recorded.
    end
  end
end
