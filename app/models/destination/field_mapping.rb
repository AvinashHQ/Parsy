# frozen_string_literal: true

module Destination
  class FieldMapping < ApplicationRecord
    self.table_name = "destination_field_mappings"

    STATUSES = %w[proposed confirmed invalid].freeze
    ORIGINS = %w[heuristic llm operator].freeze

    belongs_to :tenant
    belongs_to :database_connection, class_name: "Destination::DatabaseConnection"

    validates :source_table, inclusion: { in: ->(_record) { SourceSchema.tables } }
    validates :status, inclusion: { in: STATUSES }
    validates :origin, inclusion: { in: ORIGINS }
    validates :target_table, presence: true
    validates :source_table, uniqueness: { scope: :database_connection_id }
    validate :tenant_matches_connection
    validate :column_mappings_shape

    # A confirmed mapping that is edited must be re-validated before pushes use
    # it again; silent drift from the confirmed state is never allowed.
    before_save :reset_status_on_change

    def column_mappings=(value)
      normalized = Array(value).map { |entry| entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry }
      super(normalized)
    end

    def confirmed?
      status == "confirmed"
    end

    def mapped_source_columns
      column_mappings.map { |entry| entry["source_column"] }
    end

    def target_column_for(source_column)
      entry = column_mappings.find { |candidate| candidate["source_column"] == source_column }
      entry && entry["target_column"]
    end

    private

    def reset_status_on_change
      return if new_record? || status_changed?
      return unless column_mappings_changed? || target_table_changed?

      self.status = "proposed" if status == "confirmed"
    end

    def tenant_matches_connection
      return if database_connection.nil? || tenant_id == database_connection.tenant_id

      errors.add(:tenant, "must match the destination connection tenant")
    end

    def column_mappings_shape
      unless column_mappings.is_a?(Array) && column_mappings.all?(Hash)
        errors.add(:column_mappings, "must be an array of column mapping entries")
        return
      end

      column_mappings.each do |entry|
        source = entry["source_column"]
        target = entry["target_column"]
        if source.blank? || target.blank?
          errors.add(:column_mappings, "entries need source_column and target_column")
        elsif SourceSchema.table?(source_table) && !SourceSchema.column?(source_table, source)
          errors.add(:column_mappings, "unknown source column #{source}")
        end
      end

      sources = column_mappings.map { |entry| entry["source_column"] }
      errors.add(:column_mappings, "source columns must be unique") if sources.uniq.size != sources.size
    end
  end
end
