# frozen_string_literal: true

module Canonical
  class Payment < ValueObject
    def means = objects(:means, PaymentMean)
    def terms_text = value(:terms_text)
  end
end
