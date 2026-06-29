# frozen_string_literal: true

module Canonical
  class Reference < ValueObject
    def type = value(:type)
    def value_text = value(:value)
    def scheme = value(:scheme)
    def issue_date = value(:issue_date)
  end
end
