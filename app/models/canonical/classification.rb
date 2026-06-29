# frozen_string_literal: true

module Canonical
  class Classification < ValueObject
    def scheme = value(:scheme)
    def value_text = value(:value)
  end
end
