# frozen_string_literal: true

module Destination
  # Deterministic, idempotent writer: approved canonical invoices → rows in the
  # operator's external database, through CONFIRMED mappings only (ADR-027).
  #
  # Each invoice writes inside its own transaction so one bad invoice never
  # corrupts the batch. Idempotency keys on the mapped document_id column:
  # existing header rows update, new ones insert, and line rows are replaced
  # atomically with the header. All SQL uses adapter binds and quoted
  # identifiers; every failure surfaces as a content-free code.
  class InvoiceWriter
    class NoConfirmedMapping < StandardError; end

    DocumentResult = Struct.new(:document_id, :status, :operation, :issues, keyword_init: true) do
      def pushed?
        status == "pushed"
      end
    end

    Result = Struct.new(:results, keyword_init: true) do
      def pushed_count
        results.count(&:pushed?)
      end

      def failed_count
        results.size - pushed_count
      end

      def all_pushed?
        results.all?(&:pushed?)
      end
    end

    def self.call(revisions:, connection:, adapter: nil)
      new(revisions:, connection:, adapter:).call
    end

    # revisions: objects answering #invoice (Canonical::Invoice) and #status.
    def initialize(revisions:, connection:, adapter: nil)
      @revisions = revisions
      @connection = connection
      @adapter = adapter || Adapters.for(connection)
    end

    def call
      header_mapping = confirmed_mapping("invoices") ||
                       raise(NoConfirmedMapping, "no confirmed invoices mapping for this destination")
      lines_mapping = confirmed_mapping("line_items")

      results = @adapter.open do |session|
        @revisions.map { |revision| write_invoice(session, revision, header_mapping, lines_mapping) }
      end
      Result.new(results: results)
    end

    private

    def confirmed_mapping(source_table)
      @connection.field_mappings.find_by(source_table: source_table, status: "confirmed")
    end

    def target_columns(mapping)
      tables = Array(@connection.schema_snapshot["tables"])
      table = tables.find { |candidate| candidate["name"] == mapping.target_table }
      Array(table && table["columns"]).index_by { |column| column["name"] }
    end

    def write_invoice(session, revision, header_mapping, lines_mapping)
      document_id = revision.invoice.document_id
      rows = Canonical::Exports::NormalizedRows.call(
        invoices: [ revision.invoice ],
        review_statuses: { document_id => revision.status }
      )

      header = RowTransformer.call(row: rows.fetch("invoices").first, mapping: header_mapping, columns: target_columns(header_mapping))
      lines = lines_mapping ? rows.fetch("line_items").map { |row| RowTransformer.call(row: row, mapping: lines_mapping, columns: target_columns(lines_mapping)) } : []

      issues = header.issues + lines.flat_map(&:issues)
      return DocumentResult.new(document_id: document_id, status: "failed", operation: "validation_failed", issues: issues) if issues.any?

      operation = nil
      session.transaction do
        operation = upsert_header(session, header_mapping, header.values)
        replace_lines(session, lines_mapping, lines, document_id) if lines_mapping
      end
      DocumentResult.new(document_id: document_id, status: "pushed", operation: operation, issues: [])
    rescue Adapters::QueryFailed => error
      DocumentResult.new(document_id: document_id, status: "failed", operation: "write_failed", issues: [ { "code" => "write_failed", "detail" => error.message } ])
    end

    def upsert_header(session, mapping, values)
      table = session.quote_identifier(mapping.target_table)
      key_column = mapping.target_column_for("document_id")
      key = session.quote_identifier(key_column)
      key_value = values.fetch(key_column)

      exists = session.exec("SELECT 1 AS present FROM #{table} WHERE #{key} = ? LIMIT 1", [ key_value ]).any?
      if exists
        assignments = values.except(key_column)
        return "updated" if assignments.empty?

        set_clause = assignments.keys.map { |column| "#{session.quote_identifier(column)} = ?" }.join(", ")
        session.exec("UPDATE #{table} SET #{set_clause} WHERE #{key} = ?", assignments.values + [ key_value ])
        "updated"
      else
        column_list = values.keys.map { |column| session.quote_identifier(column) }.join(", ")
        placeholders = Array.new(values.size, "?").join(", ")
        session.exec("INSERT INTO #{table} (#{column_list}) VALUES (#{placeholders})", values.values)
        "inserted"
      end
    end

    # Line rows are replaced wholesale under the mapped document key so edits
    # and re-pushes can never leave stale or duplicated lines behind.
    def replace_lines(session, mapping, lines, document_id)
      table = session.quote_identifier(mapping.target_table)
      key = session.quote_identifier(mapping.target_column_for("document_id"))

      session.exec("DELETE FROM #{table} WHERE #{key} = ?", [ document_id ])
      lines.each do |line|
        column_list = line.values.keys.map { |column| session.quote_identifier(column) }.join(", ")
        placeholders = Array.new(line.values.size, "?").join(", ")
        session.exec("INSERT INTO #{table} (#{column_list}) VALUES (#{placeholders})", line.values.values)
      end
    end
  end
end
