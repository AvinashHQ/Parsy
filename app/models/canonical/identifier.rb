# frozen_string_literal: true

module Canonical
  class Identifier < ValueObject
    def scheme = value(:scheme)
    def value_text = value(:value)
    def issuing_country = value(:issuing_country)
    def purpose = value(:purpose)
  end
end
