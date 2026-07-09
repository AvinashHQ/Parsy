# frozen_string_literal: true

module Destination
  # Checks a field mapping against the destination's introspected schema
  # snapshot. Errors block confirmation (and therefore pushes); warnings
  # surface risks the operator may accept.
  class MappingValidator
    NUMERIC_TYPES = %w[
      numeric decimal integer bigint smallint int tinyint mediumint real float money
      double double\ precision
    ].freeze
    DATE_TYPES = %w[date datetime timestamp timestamp\ without\ time\ zone timestamp\ with\ time\ zone].freeze
    TEXT_TYPES = %w[character\ varying varchar text char character longtext mediumtext tinytext enum uuid citext].freeze

    COMPATIBLE_BUCKETS = {
      text: %i[text],
      decimal: %i[numeric text],
      integer: %i[numeric text],
      date: %i[date text]
    }.freeze

    Report = Struct.new(:errors, :warnings, keyword_init: true) do
      def valid?
        errors.empty?
      end
    end

    def self.call(mapping:, snapshot: nil)
      new(mapping:, snapshot:).call
    end

    def initialize(mapping:, snapshot: nil)
      @mapping = mapping
      @snapshot = snapshot || mapping.database_connection.schema_snapshot
    end

    def call
      @errors = []
      @warnings = []

      if target_table.nil?
        add_error(:schema_snapshot_missing_target_table, table: @mapping.target_table)
        check_source_columns
        check_required_source_columns
      else
        check_source_columns
        check_target_columns
        check_type_compatibility
        check_required_source_columns
        check_required_target_columns
        check_document_key_uniqueness
      end

      Report.new(errors: @errors, warnings: @warnings)
    end

    private

    def entries
      @mapping.column_mappings
    end

    def target_table
      @target_table ||= Array(@snapshot["tables"]).find { |table| table["name"] == @mapping.target_table }
    end

    def target_columns
      @target_columns ||= Array(target_table && target_table["columns"]).index_by { |column| column["name"] }
    end

    def check_source_columns
      entries.each do |entry|
        source = entry["source_column"]
        add_error(:unknown_source_column, source_column: source) unless SourceSchema.column?(@mapping.source_table, source)
      end

      targets = entries.map { |entry| entry["target_column"] }
      targets.tally.each do |target, count|
        add_error(:duplicate_target_column, target_column: target) if count > 1
      end
    end

    def check_target_columns
      entries.each do |entry|
        target = entry["target_column"]
        add_error(:missing_target_column, target_column: target) unless target_columns.key?(target)
      end
    end

    def check_type_compatibility
      entries.each do |entry|
        source = entry["source_column"]
        column = target_columns[entry["target_column"]]
        next unless column && SourceSchema.column?(@mapping.source_table, source)

        source_kind = SourceSchema.kind(@mapping.source_table, source)
        bucket = type_bucket(column["data_type"])
        if bucket.nil?
          add_warning(:unknown_target_type, target_column: entry["target_column"], data_type: column["data_type"])
        elsif !COMPATIBLE_BUCKETS.fetch(source_kind).include?(bucket)
          add_error(:type_mismatch, source_column: source, target_column: entry["target_column"],
                                    source_kind: source_kind.to_s, data_type: column["data_type"])
        end
      end
    end

    def check_required_source_columns
      mapped = @mapping.mapped_source_columns
      SourceSchema.required_columns(@mapping.source_table).each do |required|
        add_error(:unmapped_required_source, source_column: required) unless mapped.include?(required)
      end
    end

    # A NOT NULL target column without a database default will reject every
    # insert unless the mapping feeds it.
    def check_required_target_columns
      mapped_targets = entries.map { |entry| entry["target_column"] }
      target_columns.each_value do |column|
        next if column["nullable"] || column["default"].present? || mapped_targets.include?(column["name"])

        add_error(:unmapped_required_target, target_column: column["name"])
      end
    end

    # The idempotent upsert keys on document_id's target column; without a
    # unique constraint there, concurrent pushes could race duplicate rows.
    def check_document_key_uniqueness
      document_target = @mapping.target_column_for("document_id")
      column = document_target && target_columns[document_target]
      return unless column
      return if column["unique"]
      return unless @mapping.source_table == "invoices"

      add_warning(:document_key_not_unique, target_column: document_target)
    end

    def type_bucket(data_type)
      normalized = data_type.to_s.downcase
      return :numeric if NUMERIC_TYPES.include?(normalized)
      return :date if DATE_TYPES.include?(normalized)
      return :text if TEXT_TYPES.include?(normalized)

      nil
    end

    def add_error(code, **details)
      @errors << { "code" => code.to_s }.merge(details.transform_keys(&:to_s).transform_values(&:to_s))
    end

    def add_warning(code, **details)
      @warnings << { "code" => code.to_s }.merge(details.transform_keys(&:to_s).transform_values(&:to_s))
    end
  end
end
