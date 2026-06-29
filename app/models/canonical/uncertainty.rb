# frozen_string_literal: true

module Canonical
  class Uncertainty < ValueObject
    def code = value(:code)
    def field_paths = value(:field_paths)
    def message = value(:message)
    def candidate_values = value(:candidate_values)
  end
end
