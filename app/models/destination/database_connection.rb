# frozen_string_literal: true

module Destination
  class DatabaseConnection < ApplicationRecord
    self.table_name = "destination_database_connections"

    ADAPTERS = %w[postgresql mysql].freeze
    SSL_MODES = %w[disable prefer require].freeze

    belongs_to :tenant

    encrypts :username
    encrypts :password

    validates :label, :adapter, :host, :database_name, :username, presence: true
    validates :adapter, inclusion: { in: ADAPTERS }
    validates :ssl_mode, inclusion: { in: SSL_MODES }
    validates :label, uniqueness: { scope: :tenant_id }
    validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }

    def schema_known?
      schema_snapshot.is_a?(Hash) && schema_snapshot["tables"].present?
    end

    # Credentials must never leave through generic serialization.
    def serializable_hash(options = nil)
      options = (options || {}).dup
      if options[:only]
        options[:only] = Array(options[:only]).map(&:to_s) - %w[username password]
      else
        options[:except] = Array(options[:except]) | %i[username password]
      end
      super(options)
    end
  end
end
