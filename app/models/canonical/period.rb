# frozen_string_literal: true

module Canonical
  class Period < ValueObject
    def start_date = value(:start_date)
    def end_date = value(:end_date)
  end
end
