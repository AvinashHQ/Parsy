# frozen_string_literal: true

module Destination
  # Derives the canonical→target column mapping for one source table: exact and
  # synonym name heuristics first, then (when the tenant permits cloud egress)
  # a Gemini proposal over schema METADATA ONLY for the still-unmapped columns.
  # The result is stored as a `proposed` FieldMapping for one-time operator
  # confirmation; pushes only ever run against confirmed mappings (ADR-027).
  class MappingProposer
    class SchemaUnknown < StandardError; end
    class NoTargetTable < StandardError; end

    Result = Struct.new(:mapping, :report, :used_llm, :unmapped_source_columns, keyword_init: true)

    TABLE_NAME_HINTS = {
      "invoices" => %w[invoice invoices bill bills invoice_header invoice_headers inv_header inv],
      "line_items" => %w[
        line_items lines invoice_lines invoice_items items line_item invoice_line
        invoice_detail invoice_details line_detail
      ]
    }.freeze

    SYNONYMS = {
      "document_id" => %w[document_ref source_document_id parsy_document_id external_id external_ref source_id],
      "invoice_number" => %w[inv_no inv_num invoice_no bill_no bill_number doc_no number],
      "issue_date" => %w[invoice_date issued_on bill_date invoice_dt],
      "due_date" => %w[due_on payment_due date_due due_dt],
      "currency" => %w[currency_code curr ccy],
      "supplier_name" => %w[vendor_name vendor supplier seller_name seller],
      "buyer_name" => %w[customer_name customer client_name buyer client],
      "supplier_country" => %w[vendor_country seller_country],
      "buyer_country" => %w[customer_country client_country],
      "payable_amount" => %w[grand_total total_amount amount_due total_due balance_due amount_payable total],
      "total_tax_amount" => %w[tax_total tax_amount total_tax vat_total vat_amount gst_total gst_amount],
      "tax_exclusive_amount" => %w[subtotal sub_total net_total net_amount amount_net],
      "tax_inclusive_amount" => %w[gross_total gross_amount amount_gross],
      "line_id" => %w[line_ref line_key external_line_id source_line_id],
      "line_no" => %w[line_number position pos row_no seq sequence sr_no],
      "description" => %w[item_description line_description details particulars memo],
      "item_name" => %w[product_name item product goods_description],
      "seller_item_id" => %w[sku item_code product_code item_sku],
      "quantity" => %w[qty units qnty],
      "unit_code" => %w[uom unit unit_of_measure],
      "unit_price" => %w[price rate price_per_unit unit_cost],
      "line_net_amount" => %w[line_total net_amount line_amount amount taxable_value],
      "line_gross_amount" => %w[line_gross gross_amount line_total_gross total_with_tax]
    }.freeze

    def self.call(connection:, source_table:, target_table: nil, llm: nil)
      new(connection:, source_table:, target_table:, llm:).call
    end

    def initialize(connection:, source_table:, target_table: nil, llm: nil)
      raise ArgumentError, "unknown source table #{source_table}" unless SourceSchema.table?(source_table)

      @connection = connection
      @source_table = source_table
      @requested_target_table = target_table
      @llm = llm || MappingLlm.new
    end

    def call
      raise SchemaUnknown, "introspect the destination schema before proposing a mapping" unless @connection.schema_known?

      target_table = @requested_target_table || pick_target_table
      raise NoTargetTable, "no destination table resembles #{@source_table}" if target_table.nil?

      matched = heuristic_matches(target_table)
      used_llm = false
      if llm_allowed? && (unresolved = unmapped_columns(matched)).any?
        llm_matches(target_table, matched, unresolved).each do |source, target|
          matched[source] = target
          used_llm = true
        end
      end

      mapping = persist(target_table, matched, used_llm)
      Result.new(
        mapping: mapping,
        report: MappingValidator.call(mapping: mapping),
        used_llm: used_llm,
        unmapped_source_columns: unmapped_columns(matched)
      )
    end

    private

    def snapshot_tables
      Array(@connection.schema_snapshot["tables"])
    end

    def source_columns
      SourceSchema.column_names(@source_table)
    end

    # Deterministic pick: table-name hint plus heuristic column hits; ties fall
    # back to name order so re-proposing is stable.
    def pick_target_table
      hints = TABLE_NAME_HINTS.fetch(@source_table).map { |name| normalize(name) }
      scored = snapshot_tables.map do |table|
        hint = hints.include?(normalize(table["name"])) ? 10 : 0
        [ hint + heuristic_matches(table["name"]).size, table["name"] ]
      end
      best = scored.select { |score, _name| score.positive? }.min_by { |score, name| [ -score, name ] }
      best && best.last
    end

    def target_column_names(target_table)
      table = snapshot_tables.find { |candidate| candidate["name"] == target_table }
      Array(table && table["columns"]).map { |column| column["name"] }
    end

    def heuristic_matches(target_table)
      available = target_column_names(target_table).index_by { |name| normalize(name) }
      used = {}
      source_columns.each_with_object({}) do |source, matched|
        target = available[normalize(source)] ||
                 SYNONYMS.fetch(source, []).lazy.filter_map { |synonym| available[normalize(synonym)] }.first
        next if target.nil? || used[target]

        matched[source] = target
        used[target] = true
      end
    end

    def unmapped_columns(matched)
      source_columns - matched.keys
    end

    def llm_allowed?
      tenant = @connection.tenant
      @llm.enabled? &&
        tenant.processing_provider_allowed?(MappingLlm::PROVIDER) &&
        tenant.circuit_breaker_status == "closed"
    end

    # Failures degrade to the heuristic-only proposal; a mapping proposal must
    # never crash on cloud availability. LLM output is untrusted: sources must
    # be ones we asked about and targets must exist in the introspected schema.
    def llm_matches(target_table, matched, unresolved)
      table = snapshot_tables.find { |candidate| candidate["name"] == target_table }
      taken = matched.values.to_set
      available = target_column_names(target_table).to_set
      proposal = @llm.propose(
        source_table: @source_table,
        source_columns: unresolved.map { |name| { name: name, kind: SourceSchema.kind(@source_table, name).to_s } },
        target_table: target_table,
        target_columns: Array(table["columns"]).map { |column| { name: column["name"], data_type: column["data_type"] } }
      )
      proposal.select do |source, target|
        unresolved.include?(source) && available.include?(target) && !taken.include?(target) && taken.add(target)
      end
    rescue MappingLlm::ProposalError
      {}
    end

    def persist(target_table, matched, used_llm)
      mapping = FieldMapping.find_or_initialize_by(database_connection: @connection, source_table: @source_table)
      mapping.assign_attributes(
        tenant: @connection.tenant,
        target_table: target_table,
        column_mappings: matched.map { |source, target| { "source_column" => source, "target_column" => target } },
        status: "proposed",
        origin: used_llm ? "llm" : "heuristic"
      )
      mapping.save!
      mapping
    end

    def normalize(name)
      name.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
