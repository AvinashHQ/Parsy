# frozen_string_literal: true

require "digest"
require "json"
require "timeout"

module LocalExtraction
  class QwenSemanticAdapter
    PROMPT_ID = "local_qwen3_vl_invoice_v2"

    # Provider-independent field dictionary for Canonical Invoice v2 (ADR-026).
    # Every model that drives the extraction contract receives this so it emits the
    # exact nested field names the schema requires — the 0% schema-valid root cause
    # in 24_MODEL_SELECTION_REPORT.md §8.6 was the model guessing plausible-but-wrong
    # names (name/amount_due/ein/line_net) because the prompt only listed the 10
    # top-level keys. Derived from contracts/invoice.schema.json and
    # reference/field_dictionary.yaml; Canonical::SchemaValidator stays the
    # acceptance authority (ADR-010), so this is guidance, not a grammar.
    FIELD_CONTRACT = <<~CONTRACT
      Emit EXACTLY these field names — do not rename, translate, add, or drop keys. The JSON is
      validated with additionalProperties:false, so any extra or misspelled key fails. Every field
      listed for an object must be present on it; use null for an absent scalar and [] for an absent
      array. Objects marked "or null" may be the JSON literal null when the whole thing is absent.

      Top-level object (all keys required):
      - schema_version: the string "2.0"
      - document_id: string, at least 8 characters (if the document shows no system id, reuse the
        invoice number, extending it to 8+ characters)
      - document_type: one of invoice, tax_invoice, commercial_invoice, receipt, credit_note,
        debit_note, proforma_invoice, self_billed_invoice, unknown
      - source: object (see below)
      - locale: object (see below)
      - supplier: party object (see below)
      - buyer: party object or null
      - payee: party object or null
      - invoice: object (see below)
      - references: array of reference objects, or []
      - allowances_charges: array of allowance/charge objects, or []
      - totals: object (see below)
      - tax_breakdowns: array of tax-breakdown objects, or []
      - line_items: array of line-item objects, or []
      - payment: payment object or null
      - evidence: array of evidence objects, or [] when you cannot cite exact source text
      - uncertainties: array of uncertainty objects, or []

      party object (supplier / buyer / payee): display_name (string|null), legal_name (string|null),
        trading_name (string|null), identifiers (array — put every tax/registration id such as
        VAT/GST/EIN/ABN/PAN HERE, one entry each as {scheme, value, issuing_country, purpose} with
        purpose one of tax|business|electronic_address|government|other; NEVER a top-level "ein" or
        "tax_id"), address ({lines (array of strings), city, subdivision, postal_code, country_code}
        or null), electronic_addresses (array shaped like identifiers, or [])

      invoice object: number (string|null), issue_date, due_date, tax_point_date (dates), currency
        (ISO-4217 alpha-3 like "EUR", or null), tax_currency (like currency, or null), service_period
        ({start_date, end_date} or null), payment_terms_text (string|null)

      totals object — every value is a decimal string like "1200.00" or null. Use exactly these keys
        (NOT amount_due / subtotal / tax_total): line_extension_amount, allowance_total_amount,
        charge_total_amount, tax_exclusive_amount, total_tax_amount, tax_inclusive_amount,
        prepaid_amount, withholding_total_amount, rounding_amount, payable_amount

      tax-breakdown object: tax_type (VAT|GST|SALES_TAX|WITHHOLDING|DUTY|EXCISE|CESS|OTHER),
        component (string|null), jurisdiction_code (string|null), category_code (string|null),
        rate (decimal string like "20", no "%"), taxable_amount (decimal string|null),
        tax_amount (decimal string|null), payable_effect (add|subtract|none),
        exemption_code (string|null), exemption_reason (string|null),
        reverse_charge (true|false|null), source_label (string|null)

      line-item object: line_id (non-empty string), line_no (integer >= 1), description (string|null),
        item_name (string|null), seller_item_id (string|null), buyer_item_id (string|null),
        classifications (array of {scheme, value}, or []), quantity (decimal string|null),
        unit_code (string|null — the key is unit_code, NOT unit), unit_price (decimal string|null),
        price_base_quantity (decimal string|null), allowances_charges (array, usually []),
        line_net_amount (decimal string|null — the key is line_net_amount, NOT line_net),
        tax_breakdowns (array of tax-breakdown objects, or []), line_gross_amount (decimal string|null),
        service_period ({start_date, end_date} or null)

      source object — exactly these seven keys, NEVER add sha256 or byte_size:
        family (visual_pdf|image|hybrid_pdf_xml|ubl|cii|peppol_bis|xrechnung|fatturapa|
        india_einvoice|brazil_nfe|unknown_structured|unknown_visual),
        route (visual_model|structured_parser|hybrid_compare|quarantine), mime_type (string|null),
        profile (string|null), profile_version (string|null), page_count (integer|null),
        has_embedded_structured_data (true|false)

      locale object: document_language (BCP-47 like "en-GB", or null), script (like "Latn", or null),
        supplier_country (ISO-3166-1 alpha-2 like "GB", or null), buyer_country (like supplier_country),
        jurisdiction_candidates (array of country codes, or []), applied_region_pack ({id, version,
        resolution}; when unknown use {"id": "global_generic_v1", "version": "1.0.0",
        "resolution": "generic_fallback"})

      reference object: type (purchase_order|contract|delivery_note|original_invoice|project|
        buyer_accounting|government|tax_platform|other), value (non-empty string), scheme (string|null),
        issue_date (date|null)
      allowance/charge object: charge_indicator (true for a charge, false for an allowance),
        amount (decimal string|null), base_amount (decimal string|null), percentage (decimal string|null),
        reason_code (string|null), reason (string|null)
      payment object: means (array of {type_code, type_label, payment_reference, account_last4,
        iban_last4, bic}, or []), terms_text (string|null — the key is terms_text, NOT terms)
      evidence object: field_path (JSON pointer like "/invoice/number"), source_kind
        (visual|embedded_structured|standalone_structured), page (integer|null), source_path
        (string|null), text (string|null), bbox ({x1, y1, x2, y2} as numbers 0..1, or null)
      uncertainty object: code (UPPER_SNAKE_CASE string), field_paths (array of pointers),
        message (string), candidate_values (array)

      Formatting rules:
      - Money/amounts are pure numeric decimal strings, no currency symbol or letters ("387.54",
        not "USD 387.54" and not "GBP 1500.00").
      - Tax rate is a bare numeric decimal string, no percent sign ("8.25", not "8.25%").
      - Dates are "YYYY-MM-DD" strings or null. Country codes are ISO-3166-1 alpha-2. Currency is
        ISO-4217 alpha-3.
      - Preserve nulls for absent or ambiguous fields; do not invent values.
    CONTRACT

    # One worked example: an unrelated but fully valid Canonical Invoice v2 instance so the model
    # can pattern-match every required key (especially source/locale/evidence, which it otherwise
    # invents). Kept as its own constant so a test can assert it stays schema-valid.
    WORKED_EXAMPLE = <<~JSON
      {
        "schema_version": "2.0",
        "document_id": "doc_demo_global_0001",
        "document_type": "invoice",
        "source": {
          "family": "visual_pdf",
          "route": "visual_model",
          "mime_type": "application/pdf",
          "profile": null,
          "profile_version": null,
          "page_count": 1,
          "has_embedded_structured_data": false
        },
        "locale": {
          "document_language": "en-GB",
          "script": "Latn",
          "supplier_country": "GB",
          "buyer_country": "FR",
          "jurisdiction_candidates": ["GB", "FR"],
          "applied_region_pack": {
            "id": "global_generic_v1",
            "version": "1.0.0",
            "resolution": "generic_fallback"
          }
        },
        "supplier": {
          "display_name": "Blue Harbor Consulting Ltd",
          "legal_name": "Blue Harbor Consulting Ltd",
          "trading_name": null,
          "identifiers": [
            { "scheme": "VAT", "value": "GB123456789", "issuing_country": "GB", "purpose": "tax" }
          ],
          "address": {
            "lines": ["10 Example Street"],
            "city": "London",
            "subdivision": null,
            "postal_code": "EC1A 1AA",
            "country_code": "GB"
          },
          "electronic_addresses": []
        },
        "buyer": {
          "display_name": "Example Buyer SAS",
          "legal_name": "Example Buyer SAS",
          "trading_name": null,
          "identifiers": [
            { "scheme": "VAT", "value": "FRXX123456789", "issuing_country": "FR", "purpose": "tax" }
          ],
          "address": {
            "lines": ["20 Rue Exemple"],
            "city": "Paris",
            "subdivision": null,
            "postal_code": "75001",
            "country_code": "FR"
          },
          "electronic_addresses": []
        },
        "payee": null,
        "invoice": {
          "number": "AC-4477",
          "issue_date": "2026-06-15",
          "due_date": "2026-07-15",
          "tax_point_date": null,
          "currency": "EUR",
          "tax_currency": null,
          "service_period": null,
          "payment_terms_text": "Payment due in 30 days"
        },
        "references": [
          { "type": "purchase_order", "value": "PO-8842", "scheme": null, "issue_date": null }
        ],
        "allowances_charges": [],
        "totals": {
          "line_extension_amount": "1000.00",
          "allowance_total_amount": "0.00",
          "charge_total_amount": "0.00",
          "tax_exclusive_amount": "1000.00",
          "total_tax_amount": "200.00",
          "tax_inclusive_amount": "1200.00",
          "prepaid_amount": "0.00",
          "withholding_total_amount": "0.00",
          "rounding_amount": "0.00",
          "payable_amount": "1200.00"
        },
        "tax_breakdowns": [
          {
            "tax_type": "VAT",
            "component": null,
            "jurisdiction_code": "GB",
            "category_code": "S",
            "rate": "20",
            "taxable_amount": "1000.00",
            "tax_amount": "200.00",
            "payable_effect": "add",
            "exemption_code": null,
            "exemption_reason": null,
            "reverse_charge": false,
            "source_label": "VAT 20%"
          }
        ],
        "line_items": [
          {
            "line_id": "line_1",
            "line_no": 1,
            "description": "Consulting services",
            "item_name": "Consulting services",
            "seller_item_id": null,
            "buyer_item_id": null,
            "classifications": [],
            "quantity": "1",
            "unit_code": "EA",
            "unit_price": "1000.00",
            "price_base_quantity": "1",
            "allowances_charges": [],
            "line_net_amount": "1000.00",
            "tax_breakdowns": [
              {
                "tax_type": "VAT",
                "component": null,
                "jurisdiction_code": "GB",
                "category_code": "S",
                "rate": "20",
                "taxable_amount": "1000.00",
                "tax_amount": "200.00",
                "payable_effect": "add",
                "exemption_code": null,
                "exemption_reason": null,
                "reverse_charge": false,
                "source_label": "VAT 20%"
              }
            ],
            "line_gross_amount": "1200.00",
            "service_period": null
          }
        ],
        "payment": {
          "means": [
            {
              "type_code": "30",
              "type_label": "Credit transfer",
              "payment_reference": "AC-4477",
              "account_last4": null,
              "iban_last4": "1234",
              "bic": "EXAMPLEBIC"
            }
          ],
          "terms_text": "Payment due in 30 days"
        },
        "evidence": [
          {
            "field_path": "/invoice/number",
            "source_kind": "visual",
            "page": 1,
            "source_path": null,
            "text": "Invoice No. AC-4477",
            "bbox": null
          }
        ],
        "uncertainties": []
      }
    JSON

    PROMPT = <<~PROMPT.freeze
      Extract one invoice or credit note as Canonical Invoice v2 JSON only. Return a single JSON
      object and no explanation. Do not use model confidence to accept or reject the result;
      deterministic schema validation is authoritative.

      #{FIELD_CONTRACT}
      Worked example — an UNRELATED invoice showing the exact shape. Match its structure and key
      names, never its values:
      #{WORKED_EXAMPLE}
    PROMPT
    PROMPT_SHA256 = Digest::SHA256.hexdigest(PROMPT)
    PROVIDER_ID = "local_open_source"
    PROVIDER_VERSION = "qwen3-vl-boundary-v1"
    MODEL = "qwen3-vl:4b"
    DEFAULT_MODEL_REVISION = "latest"
    DEFAULT_QUANTIZATION = "q4_K_M"
    DEFAULT_RUNTIME = "ollama"
    DEFAULT_DEVICE = "cpu"
    # A cold vision-model load plus first-token Metal/GPU kernel warmup
    # measured ~135s locally, and a genuinely degraded (blurred/low-res) page
    # can push generation well past that; 300s leaves headroom above both
    # without waiting forever when Ollama is genuinely unreachable.
    DEFAULT_TIMEOUT_MS = 300_000
    DEFAULT_DETERMINISTIC_SETTINGS = {
      temperature: 0,
      top_p: 1,
      top_k: 1,
      seed: 0,
      max_repair_attempts: 1
    }.freeze

    class OutOfMemory < StandardError; end
    class CorruptDocument < StandardError; end

    class SemanticResult
      attr_reader :status, :candidate, :attributes, :attempts, :idempotency_key, :cached, :error_code,
                  :repair_attempts, :provenance, :failure, :provider_result

      def initialize(status:, candidate:, attributes:, attempts:, idempotency_key:, cached:, error_code:, repair_attempts:, provenance:, failure:, provider_result:)
        @status = status.to_s
        @candidate = candidate
        @attributes = attributes
        @attempts = attempts.freeze
        @idempotency_key = idempotency_key
        @cached = cached
        @error_code = error_code
        @repair_attempts = repair_attempts
        @provenance = SafeFailure.content_free(provenance)
        @failure = failure
        @provider_result = provider_result
      end

      def success? = status == "accepted"
      def rejected? = !success?
      def cached? = cached
      def failed? = status == "failed"
      def quarantined? = status == "quarantined"
      def needs_review? = status == "needs_review"

      def to_h
        {
          status: status,
          attributes: success? ? attributes : nil,
          idempotency_key: idempotency_key,
          cached: cached,
          error_code: error_code,
          repair_attempts: repair_attempts,
          provenance: provenance,
          failure: failure&.to_h,
          attempts: attempts.map(&:to_h)
        }.compact
      end
    end

    ProviderBoundary = Struct.new(:client, :adapter, keyword_init: true) do
      def call(**request)
        adapter.call_local_client(client:, request:)
      end
    end

    attr_reader :client, :cache, :model_revision, :quantization, :runtime, :device, :timeout_ms,
                :deterministic_settings

    def initialize(client:, cache: {}, provider_adapter: nil, model_revision: DEFAULT_MODEL_REVISION,
                   quantization: DEFAULT_QUANTIZATION, runtime: DEFAULT_RUNTIME, device: DEFAULT_DEVICE,
                   timeout_ms: DEFAULT_TIMEOUT_MS, deterministic_settings: {})
      @client = client
      @cache = cache
      @model_revision = model_revision.to_s
      @quantization = quantization.to_s
      @runtime = runtime.to_s
      @device = device.to_s
      @timeout_ms = Integer(timeout_ms)
      @deterministic_settings = DEFAULT_DETERMINISTIC_SETTINGS.merge(symbolize_keys(deterministic_settings)).freeze
      @provider_adapter = provider_adapter || Extraction::ProviderAdapter.new(
        provider: ProviderBoundary.new(client:, adapter: self),
        cache:
      )
    end

    def extract(inspection:, parser_output: {}, ocr_output: {}, images_bytes: [])
      request_context = request_context(inspection:, parser_output:, ocr_output:, images_bytes:)
      provider_result = provider_adapter.extract(**provider_request(request_context))

      semantic_result_from(provider_result:, route: request_context.fetch(:route), provenance: provenance_for(request_context, provider_result:))
    rescue JSON::ParserError
      failure_result(code: SafeFailure::JSON_INVALID, route: safe_route(inspection), context: request_context_or_empty(binding))
    rescue Timeout::Error
      failure_result(code: SafeFailure::TIMEOUT, route: safe_route(inspection), context: request_context_or_empty(binding))
    rescue OutOfMemory, NoMemoryError
      failure_result(code: SafeFailure::OUT_OF_MEMORY, route: safe_route(inspection), context: request_context_or_empty(binding))
    rescue CorruptDocument
      failure_result(code: SafeFailure::CORRUPT_DOCUMENT, route: safe_route(inspection), context: request_context_or_empty(binding))
    end

    def repair(result:, inspection:, allowed_paths:, parser_output: {}, ocr_output: {})
      provider_result = result.provider_result
      return repair_rejection(result:, code: SafeFailure::REPAIR_UNAVAILABLE, inspection:) unless provider_result

      if provider_result.repair_attempts >= 1
        limited = provider_adapter.repair(result: provider_result, patch: {}, allowed_paths: allowed_paths)
        return semantic_result_from(
          provider_result: limited,
          route: safe_route(inspection),
          provenance: result.provenance.merge(repair_attempts: limited.repair_attempts)
        )
      end

      request_context = request_context(inspection:, parser_output:, ocr_output:)
      patch = local_repair_patch(
        result:,
        request_context:,
        allowed_paths: allowed_paths.map { |path| normalize_pointer(path) }
      )
      repaired = provider_adapter.repair(result: provider_result, patch:, allowed_paths:)

      semantic_result_from(
        provider_result: repaired,
        route: request_context.fetch(:route),
        provenance: provenance_for(request_context, provider_result: repaired).merge(repair_attempts: repaired.repair_attempts)
      )
    rescue JSON::ParserError
      repair_rejection(result:, code: SafeFailure::JSON_INVALID, inspection:)
    rescue Timeout::Error
      repair_rejection(result:, code: SafeFailure::TIMEOUT, inspection:)
    rescue OutOfMemory, NoMemoryError
      repair_rejection(result:, code: SafeFailure::OUT_OF_MEMORY, inspection:)
    end

    def call_local_client(client:, request:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = invoke_client(client, request)
      normalized = normalize_client_response(response)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      {
        json_text: normalized.fetch(:json_text),
        metadata: client_metadata(normalized.fetch(:metadata), latency_ms: normalized.fetch(:metadata)[:latency_ms] || elapsed_ms)
      }
    end

    private

    attr_reader :provider_adapter

    def invoke_client(client, request)
      if client.respond_to?(:extract_invoice)
        client.extract_invoice(client_request(request))
      elsif client.respond_to?(:call)
        client.call(client_request(request))
      else
        raise ArgumentError, "local semantic client must respond to extract_invoice or call"
      end
    end

    def local_repair_patch(result:, request_context:, allowed_paths:)
      unless client.respond_to?(:repair_invoice)
        return {}
      end

      response = client.repair_invoice(
        repair_request(
          result:,
          request_context:,
          allowed_paths:
        )
      )
      normalized = normalize_repair_response(response)
      normalized.fetch(:patch)
    end

    def request_context(inspection:, parser_output:, ocr_output:, images_bytes: [])
      parser = hash_like(parser_output)
      ocr = hash_like(ocr_output)
      raise CorruptDocument if corrupt_output?(parser) || corrupt_output?(ocr)

      detection = inspection.detection
      {
        source_sha256: inspection.sha256,
        byte_size: inspection.byte_size,
        route: detection&.route.to_s,
        family: detection&.family,
        profile: detection&.profile,
        detection_version: detection&.version,
        page_count: parser[:page_count] || ocr[:page_count],
        parser_version: parser[:version],
        ocr_version: ocr[:version],
        parser_output: parser,
        ocr_output: ocr,
        images_bytes: Array(images_bytes)
      }
    end

    def provider_request(context)
      {
        source_sha256: context.fetch(:source_sha256),
        route: context.fetch(:route),
        region: context[:profile],
        schema_version: Canonical::Invoice::SCHEMA_VERSION,
        prompt_id: PROMPT_ID,
        prompt: PROMPT,
        provider_id: PROVIDER_ID,
        model: MODEL,
        model_version: model_revision,
        route_profile_version: route_profile_version(context),
        region_pack_version: context[:detection_version],
        document: {
          source_sha256: context.fetch(:source_sha256),
          byte_size: context[:byte_size],
          family: context[:family],
          profile: context[:profile],
          route: context[:route],
          page_count: context[:page_count]
        }.compact,
        parser_output: context.fetch(:parser_output),
        ocr_output: context.fetch(:ocr_output),
        images_bytes: context[:images_bytes] || [],
        deterministic_settings: deterministic_settings,
        prompt_sha256: PROMPT_SHA256,
        timeout_ms: timeout_ms
      }
    end

    def client_request(request)
      {
        prompt_id: PROMPT_ID,
        prompt: PROMPT,
        prompt_sha256: PROMPT_SHA256,
        schema_version: request.fetch(:schema_version),
        document: request.fetch(:document),
        parser_output: request.fetch(:parser_output),
        ocr_output: request.fetch(:ocr_output),
        images_bytes: request[:images_bytes] || [],
        deterministic_settings: deterministic_settings,
        timeout_ms: timeout_ms,
        model: MODEL,
        model_revision: model_revision,
        quantization: quantization,
        runtime: runtime,
        device: device
      }
    end

    def repair_request(result:, request_context:, allowed_paths:)
      {
        prompt_id: PROMPT_ID,
        prompt_sha256: PROMPT_SHA256,
        schema_version: Canonical::Invoice::SCHEMA_VERSION,
        document: {
          source_sha256: request_context.fetch(:source_sha256),
          byte_size: request_context[:byte_size],
          family: request_context[:family],
          profile: request_context[:profile],
          route: request_context[:route],
          page_count: request_context[:page_count]
        }.compact,
        allowed_paths: allowed_paths,
        error_code: result.error_code,
        schema_error_pointers: result.attempts.last&.schema_error_pointers || [],
        schema_error_types: result.attempts.last&.schema_error_types || [],
        deterministic_settings: deterministic_settings,
        timeout_ms: timeout_ms,
        model: MODEL,
        model_revision: model_revision,
        quantization: quantization,
        runtime: runtime,
        device: device
      }
    end

    def semantic_result_from(provider_result:, route:, provenance:)
      status = provider_result.success? ? "accepted" : "needs_review"
      failure = provider_result.success? ? nil : failure_for_provider_result(provider_result, route:)
      attributes = provider_result.success? ? provider_result.attributes : nil

      SemanticResult.new(
        status: status,
        candidate: provider_result.candidate,
        attributes: attributes,
        attempts: provider_result.attempts,
        idempotency_key: provider_result.idempotency_key,
        cached: provider_result.cached?,
        error_code: provider_result.error_code,
        repair_attempts: provider_result.repair_attempts,
        provenance: provenance,
        failure: failure,
        provider_result: provider_result
      )
    end

    def failure_for_provider_result(provider_result, route:)
      last_attempt = provider_result.attempts.last
      SafeFailure.for_code(
        provider_result.error_code,
        route:,
        metadata: {
          error_code: provider_result.error_code,
          idempotency_key: provider_result.idempotency_key,
          repair_attempts: provider_result.repair_attempts,
          schema_error_count: last_attempt&.schema_error_count,
          schema_error_pointers: last_attempt&.schema_error_pointers,
          schema_error_types: last_attempt&.schema_error_types
        }
      )
    end

    def failure_result(code:, route:, context: {})
      failure = SafeFailure.for_code(code, route:, metadata: provenance_for(context).merge(error_code: code))
      SemanticResult.new(
        status: failure.status,
        candidate: nil,
        attributes: nil,
        attempts: [],
        idempotency_key: nil,
        cached: false,
        error_code: code,
        repair_attempts: 0,
        provenance: failure.metadata,
        failure: failure,
        provider_result: nil
      )
    end

    def repair_rejection(result:, code:, inspection:)
      failure = SafeFailure.for_code(code, route: safe_route(inspection), metadata: result.provenance.merge(error_code: code))
      SemanticResult.new(
        status: failure.status,
        candidate: nil,
        attributes: nil,
        attempts: result.attempts,
        idempotency_key: result.idempotency_key,
        cached: false,
        error_code: code,
        repair_attempts: result.repair_attempts,
        provenance: failure.metadata,
        failure: failure,
        provider_result: result.provider_result
      )
    end

    def provenance_for(context, provider_result: nil)
      last_attempt = provider_result&.attempts&.last
      SafeFailure.content_free(
        {
          source_sha256: context[:source_sha256],
          route: context[:route],
          family: context[:family],
          profile: context[:profile],
          detection_version: context[:detection_version],
          byte_size: context[:byte_size],
          page_count: context[:page_count],
          parser_version: context[:parser_version],
          ocr_version: context[:ocr_version],
          model: MODEL,
          model_revision: model_revision,
          quantization: quantization,
          runtime: runtime,
          prompt_sha256: PROMPT_SHA256,
          device: device,
          latency_ms: last_attempt&.latency_ms,
          idempotency_key: provider_result&.idempotency_key,
          repair_attempts: provider_result&.repair_attempts,
          error_code: provider_result&.error_code,
          schema_error_count: last_attempt&.schema_error_count,
          schema_error_pointers: last_attempt&.schema_error_pointers,
          schema_error_types: last_attempt&.schema_error_types
        }
      )
    end

    def client_metadata(metadata, latency_ms:)
      SafeFailure.content_free(metadata).merge(
        provider_version: provider_version,
        model: MODEL,
        model_version: model_revision,
        latency_ms: latency_ms,
        model_revision: model_revision,
        quantization: quantization,
        runtime: runtime,
        prompt_sha256: PROMPT_SHA256,
        device: device
      )
    end

    def normalize_client_response(response)
      if response.respond_to?(:json_text)
        return {
          json_text: response.json_text,
          metadata: symbolize_keys(response.respond_to?(:metadata) ? response.metadata : {})
        }
      end

      if response.is_a?(Hash)
        metadata = response[:metadata] || response["metadata"] || {}
        return {
          json_text: response[:json_text] || response["json_text"] || response[:body] || response["body"] || response[:content] || response["content"],
          metadata: symbolize_keys(metadata)
        }
      end

      { json_text: response.to_s, metadata: {} }
    end

    def normalize_repair_response(response)
      if response.is_a?(Hash)
        patch = response.key?(:patch) ? response[:patch] : response["patch"]
        return { patch: patch || response }
      end

      { patch: JSON.parse(response.to_s) }
    end

    def provider_version
      [ PROVIDER_VERSION, runtime, quantization ].join("/")
    end

    def route_profile_version(context)
      Digest::SHA256.hexdigest([
        context[:route],
        context[:family],
        context[:profile],
        context[:detection_version],
        model_revision,
        quantization,
        runtime,
        device,
        PROMPT_SHA256,
        deterministic_settings.sort.to_h.to_json
      ].map(&:to_s).join("\0"))
    end

    def corrupt_output?(output)
      output[:corrupt] || output[:status].to_s == "corrupt" || Array(output[:errors]).map(&:to_s).include?(SafeFailure::CORRUPT_DOCUMENT)
    end

    def hash_like(value)
      raw = value.respond_to?(:to_h) ? value.to_h : value
      raw = {} unless raw.is_a?(Hash)
      symbolize_keys(raw)
    end

    def symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_sym] = symbolize_keys(item) }
      when Array
        value.map { |item| symbolize_keys(item) }
      else
        value
      end
    end

    def normalize_pointer(path)
      pointer = path.to_s
      pointer.start_with?("/") ? pointer : "/#{pointer}"
    end

    def safe_route(inspection)
      inspection&.route.to_s.empty? ? "local_open_source" : inspection.route.to_s
    end

    def request_context_or_empty(binding_object)
      value = binding_object.local_variable_defined?(:request_context) ? binding_object.local_variable_get(:request_context) : {}
      value.is_a?(Hash) ? value : {}
    end
  end
end
