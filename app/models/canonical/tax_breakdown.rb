# frozen_string_literal: true

module Canonical
  class TaxBreakdown < ValueObject
    def tax_type = value(:tax_type)
    def component = value(:component)
    def jurisdiction_code = value(:jurisdiction_code)
    def category_code = value(:category_code)
    def rate = value(:rate)
    def taxable_amount = value(:taxable_amount)
    def tax_amount = value(:tax_amount)
    def payable_effect = value(:payable_effect)
    def exemption_code = value(:exemption_code)
    def exemption_reason = value(:exemption_reason)
    def reverse_charge = value(:reverse_charge)
    def source_label = value(:source_label)
  end
end
