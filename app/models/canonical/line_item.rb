# frozen_string_literal: true

module Canonical
  class LineItem < ValueObject
    def line_id = value(:line_id)
    def line_no = value(:line_no)
    def description = value(:description)
    def item_name = value(:item_name)
    def seller_item_id = value(:seller_item_id)
    def buyer_item_id = value(:buyer_item_id)
    def classifications = value(:classifications)
    def quantity = value(:quantity)
    def unit_code = value(:unit_code)
    def unit_price = value(:unit_price)
    def price_base_quantity = value(:price_base_quantity)
    def allowances_charges = value(:allowances_charges)
    def line_net_amount = value(:line_net_amount)
    def tax_breakdowns = objects(:tax_breakdowns, TaxBreakdown)
    def line_gross_amount = value(:line_gross_amount)
    def service_period = value(:service_period)
  end
end
