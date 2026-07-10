# frozen_string_literal: true

module Destination
  # Deterministically converts one canonical relational row into a typed target
  # row through a mapping and the introspected column metadata. Values that
  # cannot be represented in the target column never reach SQL: coercion
  # failures and NOT NULL violations come back as content-free issues (codes
  # and column names only — never invoice values).
  class RowTransformer
    Result = Struct.new(:values, :issues, keyword_init: true) do
      def ok?
        issues.empty?
      end
    end

    def self.call(row:, mapping:, columns:)
      new(row:, mapping:, columns:).call
    end

    # columns: target column metadata indexed by name (from the schema snapshot).
    def initialize(row:, mapping:, columns:)
      @row = row
      @mapping = mapping
      @columns = columns
    end

    def call
      values = {}
      issues = []

      @mapping.column_mappings.each do |entry|
        source = entry["source_column"]
        target = entry["target_column"]
        column = @columns[target]
        raw = @row[source]

        if raw.nil?
          if column && !column["nullable"] && column["default"].blank?
            issues << issue("null_value_for_not_null_target", source, target)
          else
            values[target] = nil
          end
          next
        end

        coerced, code = coerce(raw, SourceSchema.kind(@mapping.source_table, source), column)
        if code
          issues << issue(code, source, target)
        else
          values[target] = coerced
        end
      end

      Result.new(values: values, issues: issues)
    end

    private

    def issue(code, source, target)
      { "code" => code, "source_column" => source, "target_column" => target }
    end

    # Returns [value, nil] or [nil, issue_code]. Text-bucket targets always
    # receive the canonical string form; typed targets get typed Ruby values
    # the drivers bind natively.
    def coerce(raw, kind, column)
      bucket = column ? TargetTypes.bucket(column["data_type"]) : :text

      case kind
      when :decimal
        return [ raw.to_s, nil ] if bucket == :text
        return [ nil, "type_mismatch" ] if bucket == :date

        begin
          [ BigDecimal(raw.to_s), nil ]
        rescue ArgumentError, TypeError
          [ nil, "unparseable_decimal" ]
        end
      when :integer
        return [ raw.to_s, nil ] if bucket == :text
        return [ nil, "type_mismatch" ] if bucket == :date

        begin
          [ Integer(raw), nil ]
        rescue ArgumentError, TypeError
          [ nil, "unparseable_integer" ]
        end
      when :date
        return [ raw.to_s, nil ] if bucket == :text
        return [ nil, "type_mismatch" ] if bucket == :numeric

        begin
          [ Date.iso8601(raw.to_s), nil ]
        rescue Date::Error
          [ nil, "unparseable_date" ]
        end
      else
        return [ nil, "type_mismatch" ] if %i[numeric date].include?(bucket)

        [ raw.to_s, nil ]
      end
    end
  end
end
