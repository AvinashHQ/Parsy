# frozen_string_literal: true

require "yaml"
require "set"

module Canonical
  class UniversalEngine
    APPROVED_ROUTES = %w[visual_model structured_parser hybrid_compare].freeze
    HIGH_RISK_EVIDENCE_PATHS = %w[
      /supplier/display_name
      /invoice/number
      /invoice/issue_date
      /invoice/currency
      /totals/payable_amount
    ].freeze

    def initialize(schema_validator: SchemaValidator.new, validation_rules_path: Rails.root.join("config/validation_rules.yml"), blocking_rules_path: Rails.root.join("docs/invoice-parser-m0-approved-handoff/pilot/BLOCKING_ERRORS_V1.yaml"))
      @schema_validator = schema_validator
      @validation_rules_path = Pathname(validation_rules_path)
      @blocking_rules_path = Pathname(blocking_rules_path)
    end

    def validate(input, today: Date.current, duplicate_matches: [])
      attributes = input.is_a?(Invoice) ? input.to_h : input.deep_stringify_keys
      schema_errors = schema_validator.validate(attributes)
      return schema_errors.map { |error| finding("SCHEMA_INVALID", [ error.data_pointer ], "Canonical document violates schema") } if schema_errors.any?

      invoice = input.is_a?(Invoice) ? input : Invoice.from_hash(attributes)
      findings = []
      findings.concat(document_required_findings(invoice))
      findings.concat(source_route_findings(invoice))
      findings.concat(evidence_findings(invoice))
      findings.concat(date_findings(invoice, today))
      findings.concat(currency_precision_findings(invoice))
      findings.concat(arithmetic_findings(invoice))
      findings.concat(duplicate_findings(duplicate_matches))
      findings
    end

    private

    attr_reader :schema_validator, :validation_rules_path, :blocking_rules_path

    def document_required_findings(invoice)
      findings = []
      findings << finding("DOCUMENT_TYPE_AMBIGUOUS", [ "/document_type" ], "Document type is missing or ambiguous") if invoice.document_type == "unknown"
      findings << finding("CURRENCY_MISSING_OR_AMBIGUOUS", [ "/invoice/currency" ], "Document currency is missing or ambiguous") if blank?(invoice.currency)
      findings << finding("PAYABLE_AMOUNT_MISSING", [ "/totals/payable_amount" ], "Payable amount is missing") if blank?(invoice.payable_amount)
      findings
    end

    def source_route_findings(invoice)
      return [] if APPROVED_ROUTES.include?(invoice.source.route)

      code = invoice.source.route == "quarantine" ? "UNSUPPORTED_STRUCTURED_PROFILE" : "UNKNOWN_SOURCE_ROUTE"
      [ finding(code, [ "/source/route" ], "Source route is not approved for the active profile", observed: invoice.source.route) ]
    end

    def evidence_findings(invoice)
      evidence_paths = invoice.evidence.map(&:field_path).to_set
      missing = HIGH_RISK_EVIDENCE_PATHS.reject { |path| evidence_paths.include?(path) }
      return [] if missing.empty?

      [ finding("HIGH_RISK_EVIDENCE_MISSING", missing, "High-risk field evidence is missing") ]
    end

    def date_findings(invoice, today)
      issue_date = invoice.details.issue_date
      return [] if blank?(issue_date) || Date.iso8601(issue_date) <= today

      [ finding("FUTURE_ISSUE_DATE", [ "/invoice/issue_date" ], "Issue date is in the future") ]
    rescue Date::Error
      [ finding("AMBIGUOUS_DOCUMENT_DATE", [ "/invoice/issue_date" ], "Issue date is not an unambiguous ISO date") ]
    end

    def currency_precision_findings(invoice)
      currency = invoice.currency
      return [] if blank?(currency) || !CurrencyRegistry.known?(currency)

      money_paths(invoice).filter_map do |path, value|
        next if blank?(value) || DecimalAmount.parse(value).fits_minor_units?(currency)

        finding("CURRENCY_PRECISION_MISMATCH", [ path ], "Money value exceeds currency minor-unit precision", observed: value, tolerance: CurrencyRegistry.tolerance(currency).to_s)
      rescue ArgumentError
        finding("CURRENCY_PRECISION_MISMATCH", [ path ], "Money value is not a canonical decimal string", observed: value)
      end
    end

    def arithmetic_findings(invoice)
      return [] if blank?(invoice.currency) || !CurrencyRegistry.known?(invoice.currency)

      findings = []
      findings << totals_finding(invoice, "HEADER_TOTAL_MISMATCH", "/totals/tax_exclusive_amount", total(:line_extension_amount, invoice) - total(:allowance_total_amount, invoice) + total(:charge_total_amount, invoice), invoice.totals.tax_exclusive_amount)
      findings << totals_finding(invoice, "TAX_INCLUSIVE_TOTAL_MISMATCH", "/totals/tax_inclusive_amount", total(:tax_exclusive_amount, invoice) + total(:total_tax_amount, invoice), invoice.totals.tax_inclusive_amount)
      findings << totals_finding(invoice, "PAYABLE_TOTAL_MISMATCH", "/totals/payable_amount", total(:tax_inclusive_amount, invoice) - total(:prepaid_amount, invoice) - total(:withholding_total_amount, invoice) + total(:rounding_amount, invoice), invoice.totals.payable_amount)
      findings << tax_breakdown_finding(invoice)
      findings.concat(line_item_findings(invoice))
      findings.compact
    end

    def duplicate_findings(matches)
      return [] if matches.empty?

      [ finding("PROBABLE_DUPLICATE", [ "/document_id" ], "Probable duplicate requires review confirmation", metadata: { match_count: matches.size }) ]
    end

    def totals_finding(invoice, code, path, calculated, observed)
      return nil if blank?(observed)

      observed_decimal = DecimalAmount.parse(observed)
      return nil if within_tolerance?(invoice, observed_decimal, calculated)

      finding(code, [ path ], "Totals do not reconcile", observed: observed_decimal.to_s, calculated: calculated.to_s, tolerance: CurrencyRegistry.tolerance(invoice.currency).to_s, metadata: { pilot_code: "TOTALS_DO_NOT_RECONCILE" })
    end

    def tax_breakdown_finding(invoice)
      return nil if invoice.tax_breakdowns.empty? || blank?(invoice.totals.total_tax_amount)

      calculated = invoice.tax_breakdowns.sum(DecimalAmount.parse("0")) { |breakdown| decimal_or_zero(breakdown.tax_amount) }
      observed = DecimalAmount.parse(invoice.totals.total_tax_amount)
      return nil if within_tolerance?(invoice, observed, calculated)

      finding("TAX_BREAKDOWN_CONFLICT", [ "/tax_breakdowns", "/totals/total_tax_amount" ], "Tax breakdowns do not reconcile with total tax", observed: observed.to_s, calculated: calculated.to_s, tolerance: CurrencyRegistry.tolerance(invoice.currency).to_s)
    end

    def line_item_findings(invoice)
      invoice.line_items.filter_map do |line_item|
        next if [ line_item.quantity, line_item.unit_price, line_item.price_base_quantity, line_item.line_net_amount ].any? { |value| blank?(value) }

        calculated = self.class.decimal_from_big_decimal((decimal(line_item.quantity).value * decimal(line_item.unit_price).value) / decimal(line_item.price_base_quantity).value)
        calculated -= sum_allowances(line_item)
        calculated += sum_charges(line_item)
        observed = decimal(line_item.line_net_amount)
        next if within_tolerance?(invoice, observed, calculated)

        finding("LINE_ITEM_RECONCILIATION_FAILED", [ "/line_items/#{line_item.line_no}/line_net_amount" ], "Line item net amount does not reconcile", observed: observed.to_s, calculated: calculated.to_s, tolerance: CurrencyRegistry.tolerance(invoice.currency).to_s)
      end
    end

    def money_paths(invoice)
      totals_paths = invoice.totals.to_h.map { |key, value| [ "/totals/#{key}", value ] }
      line_paths = invoice.line_items.flat_map.with_index do |line_item, index|
        line_item.to_h.slice("quantity", "unit_price", "price_base_quantity", "line_net_amount", "line_gross_amount").map { |key, value| [ "/line_items/#{index}/#{key}", value ] }
      end
      totals_paths + line_paths
    end

    def total(key, invoice)
      decimal_or_zero(invoice.totals.public_send(key))
    end

    def decimal(value)
      DecimalAmount.parse(value)
    end

    def decimal_or_zero(value)
      blank?(value) ? DecimalAmount.parse("0") : decimal(value)
    end

    def sum_allowances(line_item)
      sum_allowance_charges(line_item, false)
    end

    def sum_charges(line_item)
      sum_allowance_charges(line_item, true)
    end

    def sum_allowance_charges(line_item, charge_indicator)
      line_item.allowances_charges.select { |entry| entry.charge_indicator == charge_indicator }.sum(DecimalAmount.parse("0")) { |entry| decimal_or_zero(entry.amount) }
    end

    def within_tolerance?(invoice, observed, calculated)
      tolerance = CurrencyRegistry.tolerance(invoice.currency).value
      (observed.value - calculated.value).abs <= tolerance
    end

    def finding(code, field_paths, message, **attributes)
      Finding.new(
        code: code,
        severity: severity_for(code),
        behavior: behavior_for(code),
        field_paths: field_paths,
        message: message,
        **attributes
      )
    end

    def behavior_for(code)
      rule_index.fetch(code)["behavior"]
    end

    def severity_for(code)
      rule_index.fetch(code).fetch("severity")
    end

    def rule_index
      @rule_index ||= begin
        validation = YAML.safe_load(validation_rules_path.read, aliases: false).fetch("rules").to_h { |rule| [ rule.fetch("code"), rule ] }
        blocking = YAML.safe_load(blocking_rules_path.read, aliases: false).fetch("rules").to_h do |rule|
          [ rule.fetch("code"), rule.merge("severity" => rule.fetch("severity").upcase) ]
        end
        validation.merge(blocking)
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def self.decimal_from_big_decimal(value)
      DecimalAmount.send(:from_decimal, value)
    end
  end
end
