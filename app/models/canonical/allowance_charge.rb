# frozen_string_literal: true

module Canonical
  class AllowanceCharge < ValueObject
    def charge_indicator = value(:charge_indicator)
    def amount = value(:amount)
    def base_amount = value(:base_amount)
    def percentage = value(:percentage)
    def reason_code = value(:reason_code)
    def reason = value(:reason)

    def charge? = charge_indicator == true
    def allowance? = charge_indicator == false
  end
end
