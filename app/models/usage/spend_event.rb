# frozen_string_literal: true

module Usage
  class SpendEvent < ApplicationRecord
    self.table_name = "usage_spend_events"

    belongs_to :tenant

    STATUSES = %w[reserved paused recorded].freeze

    validates :provider, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :estimated_cents, numericality: { greater_than_or_equal_to: 0 }
  end
end
