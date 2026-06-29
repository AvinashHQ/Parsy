# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "json"

module Evaluation
  class GoldenSetRunner
    DECIMAL_PATTERN = /\A-?\d+(\.\d{1,8})?\z/
    MISSING = Object.new.freeze

    DEFAULT_VERSION_CONTEXT = {
      "schema_version" => Canonical::VersionPolicy::CURRENT_SCHEMA_VERSION,
      "prompt_hash" => "unversioned",
      "provider_version" => "unversioned",
      "parser_version" => "unversioned",
      "format_registry_version" => "unversioned",
      "currency_registry_version" => Digest::SHA256.hexdigest(JSON.generate(Canonical::CurrencyRegistry::MINOR_UNITS.sort.to_h))
    }.freeze

    def initialize(manifest_path:, extractor:, version_context: {}, schema_validator: Canonical::SchemaValidator.new)
      @manifest_path = Pathname(manifest_path)
      @extractor = extractor
      @version_context = DEFAULT_VERSION_CONTEXT.merge(stringify_keys(version_context))
      @schema_validator = schema_validator
    end

    def call
      manifest_payload = manifest_path.read
      manifest = JSON.parse(manifest_payload)
      dataset = manifest.fetch("dataset")
      cases = Array(manifest.fetch("cases"))
      default_fields = Array(manifest.fetch("fields", []))

      case_reports = cases.map do |case_config|
        evaluate_case(case_config.deep_stringify_keys, default_fields)
      end.sort_by { |case_report| [ case_report.fetch("profile"), case_report.fetch("id") ] }

      {
        "report_version" => "m2.golden_set.v1",
        "dataset" => {
          "id" => dataset.fetch("id"),
          "version" => dataset.fetch("version"),
          "manifest_sha256" => Digest::SHA256.hexdigest(manifest_payload)
        },
        "versions" => ordered_versions(version_context),
        "summary" => summarize(case_reports),
        "profiles" => summarize_profiles(case_reports),
        "cases" => case_reports
      }
    end

    private

    attr_reader :manifest_path, :extractor, :version_context, :schema_validator

    def evaluate_case(case_config, default_fields)
      expected = load_expected(case_config.fetch("expected_canonical_path"))
      extraction = normalize_extraction(extractor.call(case_config.deep_dup))
      actual = JSON.parse(extraction.fetch("json"))
      validation_errors = schema_validator.validate(actual)
      fields = Array(case_config.fetch("fields", default_fields)).map { |field| normalize_field_spec(field) }
      field_reports = fields.map { |field| compare_field(expected, actual, field) }
                            .sort_by { |field_report| field_report.fetch("pointer") }
      matched_count = field_reports.count { |field_report| field_report.fetch("matched") }
      field_count = field_reports.length

      {
        "id" => case_config.fetch("id"),
        "profile" => case_config.fetch("profile"),
        "route" => case_config.fetch("route"),
        "status" => validation_errors.empty? ? "completed" : "schema_invalid",
        "schema_error_count" => validation_errors.length,
        "field_count" => field_count,
        "matched_field_count" => matched_count,
        "accuracy" => ratio(matched_count, field_count),
        "latency_ms" => integer_or_nil(extraction.fetch("metadata").fetch("latency_ms", nil)),
        "cost" => normalize_cost(extraction.fetch("metadata").fetch("cost", {})),
        "versions" => ordered_versions(version_context.merge(extract_version_metadata(extraction.fetch("metadata")))),
        "fields" => field_reports
      }
    end

    def load_expected(path)
      pathname = Pathname(path)
      pathname = Rails.root.join(pathname) unless pathname.absolute?
      JSON.parse(pathname.read)
    end

    def normalize_extraction(result)
      if result.respond_to?(:json) && result.respond_to?(:metadata)
        json = result.json
        metadata = result.metadata
      elsif result.is_a?(Hash)
        keyed = stringify_keys(result)
        json = keyed.fetch("json") { keyed.fetch("json_text") }
        metadata = keyed.fetch("metadata", {})
      else
        raise ArgumentError, "extractor must return an object with json/metadata or a hash"
      end

      { "json" => json.to_s, "metadata" => stringify_keys(metadata || {}) }
    end

    def normalize_field_spec(field)
      return { "pointer" => field, "comparison" => "exact" } if field.is_a?(String)

      spec = field.deep_stringify_keys
      {
        "pointer" => spec.fetch("pointer"),
        "comparison" => spec.fetch("comparison", "exact")
      }
    end

    def compare_field(expected, actual, field)
      pointer = field.fetch("pointer")
      comparison = field.fetch("comparison")
      expected_value = resolve_pointer(expected, pointer)
      actual_value = resolve_pointer(actual, pointer)
      matched, error_code = field_match(expected_value, actual_value, comparison)

      {
        "pointer" => pointer,
        "comparison" => comparison,
        "matched" => matched,
        "expected_present" => !expected_value.equal?(MISSING),
        "actual_present" => !actual_value.equal?(MISSING),
        "error_code" => error_code
      }
    end

    def field_match(expected_value, actual_value, comparison)
      return [ false, "FIELD_MISSING" ] if expected_value.equal?(MISSING) || actual_value.equal?(MISSING)

      case comparison
      when "exact"
        [ expected_value == actual_value, expected_value == actual_value ? nil : "FIELD_MISMATCH" ]
      when "normalized"
        expected_normalized = normalize_scalar(expected_value)
        actual_normalized = normalize_scalar(actual_value)
        [ expected_normalized == actual_normalized, expected_normalized == actual_normalized ? nil : "FIELD_MISMATCH" ]
      when "decimal"
        expected_decimal = parse_decimal(expected_value)
        actual_decimal = parse_decimal(actual_value)
        return [ false, "DECIMAL_INVALID" ] unless expected_decimal && actual_decimal

        [ expected_decimal == actual_decimal, expected_decimal == actual_decimal ? nil : "FIELD_MISMATCH" ]
      else
        raise ArgumentError, "unsupported field comparison #{comparison.inspect}"
      end
    end

    def resolve_pointer(document, pointer)
      raise ArgumentError, "JSON pointer must start with /" unless pointer.start_with?("/")

      pointer.split("/")[1..].reduce(document) do |current, token|
        return MISSING if current.equal?(MISSING)

        key = token.gsub("~1", "/").gsub("~0", "~")
        if current.is_a?(Array)
          return MISSING unless key.match?(/\A\d+\z/)

          current.fetch(key.to_i, MISSING)
        elsif current.is_a?(Hash)
          current.fetch(key, MISSING)
        else
          MISSING
        end
      end
    end

    def normalize_scalar(value)
      return value unless value.is_a?(String)

      normalized = value.unicode_normalize(:nfkc)
      normalized.strip.gsub(/\s+/, " ").downcase
    end

    def parse_decimal(value)
      return nil unless value.is_a?(String) && value.match?(DECIMAL_PATTERN)

      BigDecimal(value)
    end

    def extract_version_metadata(metadata)
      keyed = stringify_keys(metadata)
      %w[schema_version prompt_hash provider_version parser_version format_registry_version currency_registry_version].each_with_object({}) do |key, extracted|
        extracted[key] = keyed[key] if keyed.key?(key)
      end
    end

    def ordered_versions(versions)
      keyed = stringify_keys(versions)
      {
        "schema_version" => keyed.fetch("schema_version"),
        "prompt_hash" => keyed.fetch("prompt_hash"),
        "provider_version" => keyed.fetch("provider_version"),
        "parser_version" => keyed.fetch("parser_version"),
        "format_registry_version" => keyed.fetch("format_registry_version"),
        "currency_registry_version" => keyed.fetch("currency_registry_version")
      }
    end

    def normalize_cost(cost)
      keyed = stringify_keys(cost || {})
      amount = keyed.fetch("amount", keyed.fetch("usd", nil))

      {
        "currency" => keyed.fetch("currency", amount.nil? ? nil : "USD"),
        "amount" => amount.nil? ? nil : decimal_string(amount),
        "input_tokens" => integer_or_nil(keyed.fetch("input_tokens", nil)),
        "output_tokens" => integer_or_nil(keyed.fetch("output_tokens", nil))
      }
    end

    def summarize(case_reports)
      field_count = case_reports.sum { |case_report| case_report.fetch("field_count") }
      matched_count = case_reports.sum { |case_report| case_report.fetch("matched_field_count") }

      {
        "case_count" => case_reports.length,
        "field_count" => field_count,
        "matched_field_count" => matched_count,
        "accuracy" => ratio(matched_count, field_count),
        "latency_ms" => case_reports.sum { |case_report| case_report.fetch("latency_ms").to_i },
        "cost" => summarize_cost(case_reports)
      }
    end

    def summarize_profiles(case_reports)
      case_reports.group_by { |case_report| case_report.fetch("profile") }.sort.map do |profile, profile_cases|
        field_count = profile_cases.sum { |case_report| case_report.fetch("field_count") }
        matched_count = profile_cases.sum { |case_report| case_report.fetch("matched_field_count") }

        {
          "profile" => profile,
          "case_count" => profile_cases.length,
          "field_count" => field_count,
          "matched_field_count" => matched_count,
          "accuracy" => ratio(matched_count, field_count),
          "routes" => profile_cases.group_by { |case_report| case_report.fetch("route") }.sort.map { |route, route_cases| summarize_route(route, route_cases) }
        }
      end
    end

    def summarize_route(route, route_cases)
      field_count = route_cases.sum { |case_report| case_report.fetch("field_count") }
      matched_count = route_cases.sum { |case_report| case_report.fetch("matched_field_count") }

      {
        "route" => route,
        "case_count" => route_cases.length,
        "field_count" => field_count,
        "matched_field_count" => matched_count,
        "accuracy" => ratio(matched_count, field_count),
        "latency_ms" => route_cases.sum { |case_report| case_report.fetch("latency_ms").to_i },
        "cost" => summarize_cost(route_cases)
      }
    end

    def summarize_cost(case_reports)
      currencies = case_reports.map { |case_report| case_report.fetch("cost").fetch("currency") }.compact.uniq.sort
      amounts = case_reports.map { |case_report| case_report.fetch("cost").fetch("amount") }.compact
      amount = amounts.reduce(BigDecimal("0")) { |sum, value| sum + BigDecimal(value) }

      {
        "currency" => currencies.length == 1 ? currencies.first : nil,
        "amount" => decimal_string(amount.to_s("F")),
        "input_tokens" => case_reports.sum { |case_report| case_report.fetch("cost").fetch("input_tokens").to_i },
        "output_tokens" => case_reports.sum { |case_report| case_report.fetch("cost").fetch("output_tokens").to_i }
      }
    end

    def ratio(numerator, denominator)
      return "0.000000" if denominator.zero?

      format("%.6f", numerator.fdiv(denominator))
    end

    def decimal_string(value)
      BigDecimal(value.to_s).to_s("F")
    end

    def integer_or_nil(value)
      value.nil? ? nil : Integer(value)
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          result[key.to_s] = stringify_keys(item)
        end
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end
  end
end
