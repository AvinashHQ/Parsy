# frozen_string_literal: true

module Canonical
  class Party < ValueObject
    def display_name = value(:display_name)
    def legal_name = value(:legal_name)
    def trading_name = value(:trading_name)
    def identifiers = objects(:identifiers, Identifier)
    def address = object(:address, Address)
    def electronic_addresses = objects(:electronic_addresses, Identifier)
  end
end
