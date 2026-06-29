# frozen_string_literal: true

module Canonical
  class Address < ValueObject
    def lines = value(:lines)
    def city = value(:city)
    def subdivision = value(:subdivision)
    def postal_code = value(:postal_code)
    def country_code = value(:country_code)
  end
end
