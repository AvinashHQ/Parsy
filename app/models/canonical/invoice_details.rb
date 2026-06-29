# frozen_string_literal: true

module Canonical
  class InvoiceDetails < ValueObject
    def number = value(:number)
    def issue_date = value(:issue_date)
    def due_date = value(:due_date)
    def tax_point_date = value(:tax_point_date)
    def currency = value(:currency)
    def tax_currency = value(:tax_currency)
    def service_period = value(:service_period)
    def payment_terms_text = value(:payment_terms_text)
  end
end
