# frozen_string_literal: true

module Destination
  # One-time operator confirmation gate: a mapping only becomes usable by the
  # push path when it validates cleanly against the destination's introspected
  # schema. Invalid mappings are marked so the UI shows exactly why.
  class MappingConfirmer
    Result = Struct.new(:confirmed, :report, keyword_init: true) do
      def confirmed?
        confirmed
      end
    end

    def self.call(mapping:, validator: MappingValidator)
      report = validator.call(mapping: mapping)
      if report.valid?
        mapping.update!(status: "confirmed")
      else
        mapping.update!(status: "invalid")
      end
      Result.new(confirmed: report.valid?, report: report)
    end
  end
end
