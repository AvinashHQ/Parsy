# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class UncertaintyTest < Minitest::Test
    def test_exposes_uncertainty_fields_through_value_object_api
      uncertainty = Uncertainty.from_hash(
        code: "AMBIGUOUS_TOTAL",
        field_paths: [ "/totals/payable_amount", "/line_items/0/line_net_amount" ],
        message: "Two totals could be payable.",
        candidate_values: [ "100.00", "110.00" ]
      )

      assert_equal "AMBIGUOUS_TOTAL", uncertainty.code
      assert_equal [ "/totals/payable_amount", "/line_items/0/line_net_amount" ], uncertainty.field_paths
      assert_equal "Two totals could be payable.", uncertainty.message
      assert_equal [ "100.00", "110.00" ], uncertainty.candidate_values
      assert_equal "AMBIGUOUS_TOTAL", uncertainty[:code]
      assert_equal [ "100.00", "110.00" ], uncertainty["candidate_values"]
    end

    def test_invoice_uncertainties_preserve_field_arrays_and_nested_candidate_values
      invoice = Invoice.from_hash(
        "uncertainties" => [
          {
            "code" => "LINE_TOTAL_AMBIGUOUS",
            "field_paths" => [
              "/line_items/0/line_net_amount",
              "/totals/line_extension_amount"
            ],
            "message" => "Line and total disagree.",
            "candidate_values" => [
              { "field_path" => "/line_items/0/line_net_amount", "value" => "99.50" },
              { "field_path" => "/totals/line_extension_amount", "value" => "100.00" },
              [ "subtotal", "tax", "payable" ]
            ]
          }
        ]
      )

      uncertainty = invoice.uncertainties.first

      assert_instance_of Uncertainty, uncertainty
      assert_equal [ "/line_items/0/line_net_amount", "/totals/line_extension_amount" ], uncertainty.field_paths
      assert_equal(
        [
          { "field_path" => "/line_items/0/line_net_amount", "value" => "99.50" },
          { "field_path" => "/totals/line_extension_amount", "value" => "100.00" },
          [ "subtotal", "tax", "payable" ]
        ],
        uncertainty.candidate_values
      )
      assert_equal uncertainty.candidate_values, uncertainty.to_h.fetch("candidate_values")
    end
  end
end
