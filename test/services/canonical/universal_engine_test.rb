# frozen_string_literal: true

require "canonical_test_helper"

module Canonical
  class UniversalEngineTest < Minitest::Test
    FIXTURE_DIR = Rails.root.join("test/fixtures/files/canonical")

    def test_schema_invalid_returns_stable_finding_without_invoice_content
      attributes = valid_attributes
      attributes.delete("document_type")

      findings = Canonical::UniversalEngine.new.validate(attributes)

      assert_equal [ "SCHEMA_INVALID" ], findings.map(&:code)
      assert findings.first.critical?
      assert findings.none? { |finding| finding.message.include?("Northstar") }
    end

    def test_missing_currency_and_payable_emit_pilot_policy_codes
      attributes = valid_attributes
      attributes["invoice"]["currency"] = nil
      attributes["totals"]["payable_amount"] = nil

      findings = Canonical::UniversalEngine.new.validate(attributes)

      assert_includes findings.map(&:code), "CURRENCY_MISSING_OR_AMBIGUOUS"
      assert_includes findings.map(&:code), "PAYABLE_AMOUNT_MISSING"
      assert findings.find { |finding| finding.code == "CURRENCY_MISSING_OR_AMBIGUOUS" }.critical?
    end

    def test_high_risk_evidence_missing_keeps_behavior_separate_from_severity
      attributes = valid_attributes
      attributes["evidence"] = []

      finding = Canonical::UniversalEngine.new.validate(attributes).find { |candidate| candidate.code == "HIGH_RISK_EVIDENCE_MISSING" }

      assert_equal "HIGH", finding.severity
      assert_equal "block_export", finding.behavior
      assert_includes finding.field_paths, "/invoice/currency"
    end

    def test_header_total_mismatch_is_critical_arithmetic_finding
      attributes = valid_attributes
      attributes["totals"]["tax_exclusive_amount"] = "999.00"

      finding = Canonical::UniversalEngine.new.validate(attributes).find { |candidate| candidate.code == "HEADER_TOTAL_MISMATCH" }

      assert_equal "CRITICAL", finding.severity
      assert_equal "TOTALS_DO_NOT_RECONCILE", finding.metadata.fetch(:pilot_code)
      assert_equal "999", finding.observed
      assert_equal "1000", finding.calculated
    end

    def test_tax_breakdown_conflict_is_stable_finding
      attributes = valid_attributes
      attributes["tax_breakdowns"][0]["tax_amount"] = "199.00"

      finding = Canonical::UniversalEngine.new.validate(attributes).find { |candidate| candidate.code == "TAX_BREAKDOWN_CONFLICT" }

      assert_equal "HIGH", finding.severity
      assert_equal "require_confirmation", finding.behavior
      assert_equal "200", finding.observed
      assert_equal "199", finding.calculated
    end

    def test_line_item_reconciliation_failed_is_stable_finding
      attributes = valid_attributes
      attributes["line_items"][0]["line_net_amount"] = "999.00"

      finding = Canonical::UniversalEngine.new.validate(attributes).find { |candidate| candidate.code == "LINE_ITEM_RECONCILIATION_FAILED" }

      assert_equal "HIGH", finding.severity
      assert_equal "require_confirmation", finding.behavior
      assert_equal "999", finding.observed
      assert_equal "1000", finding.calculated
    end

    def test_currency_precision_mismatch_uses_minor_unit_tolerance
      attributes = JSON.parse(FIXTURE_DIR.join("fix_003_zero_minor_unit_jpy.json").read)
      attributes["totals"]["payable_amount"] = "10000.50"

      finding = Canonical::UniversalEngine.new.validate(attributes).find { |candidate| candidate.code == "CURRENCY_PRECISION_MISMATCH" }

      assert_equal "HIGH", finding.severity
      assert_equal "1", finding.tolerance
    end

    def test_future_issue_date_is_high_severity_date_finding
      attributes = valid_attributes
      attributes["invoice"]["issue_date"] = "2099-01-01"

      finding = Canonical::UniversalEngine.new.validate(attributes, today: Date.new(2026, 6, 29)).find { |candidate| candidate.code == "FUTURE_ISSUE_DATE" }

      assert_equal "HIGH", finding.severity
      assert_equal [ "/invoice/issue_date" ], finding.field_paths
    end

    private

    def valid_attributes
      attributes = JSON.parse(FIXTURE_DIR.join("fix_005_generic_vat_eur.json").read)
      attributes["evidence"] += [
        evidence_for("/supplier/display_name", "Northstar Services Ltd"),
        evidence_for("/invoice/currency", "EUR")
      ]
      attributes
    end

    def evidence_for(path, text)
      {
        "field_path" => path,
        "source_kind" => "visual",
        "page" => 1,
        "source_path" => nil,
        "text" => text,
        "bbox" => nil
      }
    end
  end
end
