# frozen_string_literal: true

require "digest"

module Intake
  class StructuredInvoiceAdapter
    Result = Data.define(:status, :canonical, :errors, :detection, :observability) do
      def mapped? = status == "mapped"
      def quarantined? = status == "quarantined"
    end

    def initialize(inspector: UploadInspector.new, schema_validator: Canonical::SchemaValidator.new)
      @inspector = inspector
      @schema_validator = schema_validator
    end

    def call(xml:, filename: "invoice.xml", embedded: false)
      inspection = inspector.inspect_bytes(xml.to_s, filename: filename, content_type: "application/xml")
      detection = inspection.detection
      return quarantine(detection, inspection.rejection_code || "UNSUPPORTED_STRUCTURED_FORMAT") if inspection.quarantined? || detection.route != "structured_parser"
      return quarantine(detection, inspection.rejection_code) if inspection.rejected?

      attributes =
        case detection.profile
        when "oasis_ubl_invoice"
          map_ubl(xml.to_s, detection:, embedded:)
        when "uncefact_cii"
          map_cii(xml.to_s, detection:, embedded:)
        else
          return quarantine(detection, "UNSUPPORTED_STRUCTURED_FORMAT")
        end

      errors = schema_validator.validate(attributes)
      return Result.new(status: "quarantined", canonical: nil, errors: [ "SCHEMA_INVALID" ], detection: detection, observability: observability(detection, "SCHEMA_INVALID")) if errors.any?

      Result.new(status: "mapped", canonical: Canonical::Invoice.new(attributes), errors: [], detection: detection, observability: observability(detection, nil))
    end

    private

    attr_reader :inspector, :schema_validator

    def quarantine(detection, code)
      Result.new(status: "quarantined", canonical: nil, errors: [ code || "UNSUPPORTED_STRUCTURED_FORMAT" ], detection: detection, observability: observability(detection, code))
    end

    def map_ubl(xml, detection:, embedded:)
      number = first_tag(xml, "ID")
      issue_date = first_tag(xml, "IssueDate")
      currency = first_tag(xml, "DocumentCurrencyCode")
      supplier = first_nested_tag(xml, "AccountingSupplierParty", "Name")
      payable = first_tag_with_attribute(xml, "PayableAmount") || first_tag(xml, "PayableAmount")
      tax_exclusive = first_tag_with_attribute(xml, "TaxExclusiveAmount") || payable
      tax_inclusive = first_tag_with_attribute(xml, "TaxInclusiveAmount") || payable
      tax_amount = first_tag_with_attribute(xml, "TaxAmount") || "0"
      line_amount = first_tag_with_attribute(xml, "LineExtensionAmount") || tax_exclusive
      description = first_nested_tag(xml, "InvoiceLine", "Name") || "Structured invoice line"
      quantity = first_tag_with_attribute(xml, "InvoicedQuantity") || "1"
      unit_price = first_nested_tag(xml, "Price", "PriceAmount") || line_amount

      canonical_document(
        source_family: detection.family,
        source_route: detection.route,
        source_profile: detection.profile,
        source_profile_version: detection.version,
        mime_type: "application/xml",
        embedded: embedded,
        document_id_seed: xml,
        document_type: xml.include?("CreditNote") ? "credit_note" : "invoice",
        number: number,
        issue_date: issue_date,
        currency: currency,
        supplier_name: supplier,
        totals: totals(line_extension: line_amount, tax_exclusive: tax_exclusive, tax_amount: tax_amount, tax_inclusive: tax_inclusive, payable: payable),
        line: line(description: description, quantity: quantity, unit_price: unit_price, amount: line_amount),
        evidence_kind: embedded ? "embedded_structured" : "standalone_structured"
      )
    end

    def map_cii(xml, detection:, embedded:)
      number = first_nested_tag(xml, "ExchangedDocument", "ID") || first_tag(xml, "ID")
      issue_date = first_tag(xml, "DateTimeString")
      currency = first_tag(xml, "InvoiceCurrencyCode")
      supplier = first_nested_tag(xml, "SellerTradeParty", "Name")
      payable = first_tag(xml, "DuePayableAmount") || first_tag(xml, "GrandTotalAmount")
      tax_exclusive = first_tag(xml, "TaxBasisTotalAmount") || payable
      tax_inclusive = first_tag(xml, "GrandTotalAmount") || payable
      tax_amount = first_tag(xml, "TaxTotalAmount") || "0"
      line_amount = first_nested_tag(xml, "SpecifiedLineTradeSettlement", "LineTotalAmount") || tax_exclusive
      description = first_nested_tag(xml, "SpecifiedTradeProduct", "Name") || "Structured invoice line"
      quantity = first_tag(xml, "BilledQuantity") || "1"
      unit_price = first_nested_tag(xml, "GrossPriceProductTradePrice", "ChargeAmount") || line_amount

      canonical_document(
        source_family: detection.family,
        source_route: detection.route,
        source_profile: detection.profile,
        source_profile_version: detection.version,
        mime_type: "application/xml",
        embedded: embedded,
        document_id_seed: xml,
        document_type: "invoice",
        number: number,
        issue_date: issue_date,
        currency: currency,
        supplier_name: supplier,
        totals: totals(line_extension: line_amount, tax_exclusive: tax_exclusive, tax_amount: tax_amount, tax_inclusive: tax_inclusive, payable: payable),
        line: line(description: description, quantity: quantity, unit_price: unit_price, amount: line_amount),
        evidence_kind: embedded ? "embedded_structured" : "standalone_structured"
      )
    end

    def canonical_document(source_family:, source_route:, source_profile:, source_profile_version:, mime_type:, embedded:, document_id_seed:, document_type:, number:, issue_date:, currency:, supplier_name:, totals:, line:, evidence_kind:)
      {
        "schema_version" => Canonical::Invoice::SCHEMA_VERSION,
        "document_id" => "structured_#{Digest::SHA256.hexdigest(document_id_seed)[0, 16]}",
        "document_type" => document_type,
        "source" => {
          "family" => source_family,
          "route" => source_route,
          "mime_type" => mime_type,
          "profile" => source_profile,
          "profile_version" => source_profile_version,
          "page_count" => nil,
          "has_embedded_structured_data" => embedded
        },
        "locale" => {
          "document_language" => nil,
          "script" => nil,
          "supplier_country" => nil,
          "buyer_country" => nil,
          "jurisdiction_candidates" => [],
          "applied_region_pack" => {
            "id" => Canonical::VersionPolicy::CURRENT_PROFILE_ID,
            "version" => Canonical::VersionPolicy::CURRENT_PROFILE_VERSION,
            "resolution" => "generic_fallback"
          }
        },
        "supplier" => party(supplier_name),
        "buyer" => nil,
        "payee" => nil,
        "invoice" => {
          "number" => number,
          "issue_date" => normalize_date(issue_date),
          "due_date" => nil,
          "tax_point_date" => nil,
          "currency" => currency,
          "tax_currency" => nil,
          "service_period" => nil,
          "payment_terms_text" => nil
        },
        "references" => [],
        "allowances_charges" => [],
        "totals" => totals,
        "tax_breakdowns" => [],
        "line_items" => [ line ],
        "payment" => nil,
        "evidence" => evidence(number:, issue_date: normalize_date(issue_date), currency:, payable: totals.fetch("payable_amount"), kind: evidence_kind),
        "uncertainties" => []
      }
    end

    def party(name)
      {
        "display_name" => name,
        "legal_name" => name,
        "trading_name" => nil,
        "identifiers" => [],
        "address" => nil,
        "electronic_addresses" => []
      }
    end

    def totals(line_extension:, tax_exclusive:, tax_amount:, tax_inclusive:, payable:)
      {
        "line_extension_amount" => decimal_or_nil(line_extension),
        "allowance_total_amount" => "0",
        "charge_total_amount" => "0",
        "tax_exclusive_amount" => decimal_or_nil(tax_exclusive),
        "total_tax_amount" => decimal_or_nil(tax_amount),
        "tax_inclusive_amount" => decimal_or_nil(tax_inclusive),
        "prepaid_amount" => "0",
        "withholding_total_amount" => "0",
        "rounding_amount" => "0",
        "payable_amount" => decimal_or_nil(payable)
      }
    end

    def line(description:, quantity:, unit_price:, amount:)
      {
        "line_id" => "line_1",
        "line_no" => 1,
        "description" => description,
        "item_name" => description,
        "seller_item_id" => nil,
        "buyer_item_id" => nil,
        "classifications" => [],
        "quantity" => decimal_or_nil(quantity),
        "unit_code" => nil,
        "unit_price" => decimal_or_nil(unit_price),
        "price_base_quantity" => "1",
        "allowances_charges" => [],
        "line_net_amount" => decimal_or_nil(amount),
        "tax_breakdowns" => [],
        "line_gross_amount" => decimal_or_nil(amount),
        "service_period" => nil
      }
    end

    def evidence(number:, issue_date:, currency:, payable:, kind:)
      [ [ "/invoice/number", number, "/*[local-name()='Invoice']/*[local-name()='ID']" ],
        [ "/invoice/issue_date", issue_date, "//*[local-name()='IssueDate' or local-name()='DateTimeString']" ],
        [ "/invoice/currency", currency, "//*[local-name()='DocumentCurrencyCode' or local-name()='InvoiceCurrencyCode']" ],
        [ "/totals/payable_amount", payable, "//*[local-name()='PayableAmount' or local-name()='DuePayableAmount']" ] ].filter_map do |field_path, text, source_path|
        next if text.nil?

        {
          "field_path" => field_path,
          "source_kind" => kind,
          "page" => nil,
          "source_path" => source_path,
          "text" => text.to_s[0, 300],
          "bbox" => nil
        }
      end
    end

    def first_tag(xml, tag)
      escaped = Regexp.escape(tag)
      xml[%r{<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?#{escaped}\b(?:\s[^>]*)?>(.*?)</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?#{escaped}>}mi, 1]&.strip
    end

    def first_tag_with_attribute(xml, tag)
      first_tag(xml, tag)
    end

    def first_nested_tag(xml, parent, child)
      escaped_parent = Regexp.escape(parent)
      parent_body = xml[%r{<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?#{escaped_parent}\b(?:\s[^>]*)?>(.*?)</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?#{escaped_parent}>}mi, 1]
      parent_body && first_tag(parent_body, child)
    end

    def normalize_date(value)
      return nil if value.blank?
      return value[0, 4] + "-" + value[4, 2] + "-" + value[6, 2] if value.match?(/\A\d{8}\z/)

      value
    end

    def decimal_or_nil(value)
      return nil if value.blank?

      value.to_s.strip
    end

    def observability(detection, error_code)
      {
        route: detection&.route,
        family: detection&.family,
        profile: detection&.profile,
        registry_version: detection&.version,
        error_code: error_code
      }.compact
    end
  end
end
