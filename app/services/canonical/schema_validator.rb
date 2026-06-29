# frozen_string_literal: true

require "json"
require "json_schemer"

module Canonical
  class SchemaValidator
    Error = Data.define(:data_pointer, :schema_pointer, :type, :details) do
      def message
        details.fetch("error", type.to_s)
      end
    end

    SCHEMA_PATH = Rails.root.join("contracts/invoice.schema.json")

    def initialize(schema_path: SCHEMA_PATH)
      @schema_path = Pathname(schema_path)
    end

    def valid?(attributes)
      validate(attributes).empty?
    end

    def validate(attributes)
      schemer.validate(attributes).map do |error|
        Error.new(
          data_pointer: error.fetch("data_pointer", ""),
          schema_pointer: error.fetch("schema_pointer", ""),
          type: error.fetch("type", nil),
          details: error
        )
      end
    end

    private

    attr_reader :schema_path

    def schemer
      @schemer ||= JSONSchemer.schema(JSON.parse(schema_path.read))
    end
  end
end
