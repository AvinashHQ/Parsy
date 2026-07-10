# frozen_string_literal: true

module Destination
  # Buckets destination column types (as reported by information_schema on
  # PostgreSQL and MySQL) into the coarse kinds the mapping validator and row
  # transformer reason about.
  module TargetTypes
    NUMERIC_TYPES = %w[
      numeric decimal integer bigint smallint int tinyint mediumint real float money
      double double\ precision
    ].freeze
    DATE_TYPES = %w[date datetime timestamp timestamp\ without\ time\ zone timestamp\ with\ time\ zone].freeze
    TEXT_TYPES = %w[character\ varying varchar text char character longtext mediumtext tinytext enum uuid citext].freeze

    def self.bucket(data_type)
      normalized = data_type.to_s.downcase
      return :numeric if NUMERIC_TYPES.include?(normalized)
      return :date if DATE_TYPES.include?(normalized)
      return :text if TEXT_TYPES.include?(normalized)

      nil
    end
  end
end
