# frozen_string_literal: true

module Canonical
  class PaymentMean < ValueObject
    def type_code = value(:type_code)
    def type_label = value(:type_label)
    def payment_reference = value(:payment_reference)
    def account_last4 = value(:account_last4)
    def iban_last4 = value(:iban_last4)
    def bic = value(:bic)
  end
end
