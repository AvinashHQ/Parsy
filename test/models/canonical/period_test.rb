# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class PeriodTest < Minitest::Test
    def test_exposes_service_period_dates_through_value_object_api
      period = Period.from_hash(start_date: "2026-06-01", end_date: "2026-06-30")

      assert_equal "2026-06-01", period.start_date
      assert_equal "2026-06-30", period.end_date
      assert_equal "2026-06-01", period[:start_date]
      assert_equal "2026-06-30", period["end_date"]
      assert_equal({ "start_date" => "2026-06-01", "end_date" => "2026-06-30" }, period.to_h)
    end

    def test_invoice_details_and_line_items_preserve_nested_period_values
      invoice = Invoice.from_hash(
        "invoice" => {
          "service_period" => {
            "start_date" => "2026-04-01",
            "end_date" => "2026-04-30"
          }
        },
        "line_items" => [
          {
            "line_id" => "1",
            "service_period" => {
              "start_date" => "2026-04-15",
              "end_date" => "2026-04-20"
            }
          }
        ]
      )

      assert_instance_of Period, invoice.details.service_period
      assert_equal "2026-04-01", invoice.details.service_period.start_date
      assert_equal "2026-04-30", invoice.details.service_period.end_date

      line_period = invoice.line_items.first.service_period
      assert_instance_of Period, line_period
      assert_equal "2026-04-15", line_period.start_date
      assert_equal "2026-04-20", line_period.end_date
    end
  end
end
