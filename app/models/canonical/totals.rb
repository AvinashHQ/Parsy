# frozen_string_literal: true

module Canonical
  class Totals < ValueObject
    def line_extension_amount = value(:line_extension_amount)
    def allowance_total_amount = value(:allowance_total_amount)
    def charge_total_amount = value(:charge_total_amount)
    def tax_exclusive_amount = value(:tax_exclusive_amount)
    def total_tax_amount = value(:total_tax_amount)
    def tax_inclusive_amount = value(:tax_inclusive_amount)
    def prepaid_amount = value(:prepaid_amount)
    def withholding_total_amount = value(:withholding_total_amount)
    def rounding_amount = value(:rounding_amount)
    def payable_amount = value(:payable_amount)
  end
end
