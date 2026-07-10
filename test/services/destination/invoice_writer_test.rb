# frozen_string_literal: true

require "test_helper"
require "json"

module Destination
  class InvoiceWriterTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    SNAPSHOT = {
      "tables" => [
        {
          "name" => "customer_invoices",
          "columns" => [
            { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => true },
            { "name" => "inv_no", "data_type" => "character varying", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "grand_total", "data_type" => "numeric", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
          ]
        },
        {
          "name" => "customer_lines",
          "columns" => [
            { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "line_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "amount", "data_type" => "numeric", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
          ]
        }
      ]
    }.freeze

    FakeRevision = Struct.new(:invoice, :status)

    # Records every statement; configurable existing keys (for the update path)
    # and per-SQL failures (for isolation).
    class FakeSession
      attr_reader :statements

      def initialize(existing_keys: [], fail_on: nil)
        @existing_keys = existing_keys
        @fail_on = fail_on
        @statements = []
      end

      def exec(sql, params = [])
        raise Adapters::QueryFailed, "destination query failed (Fake)" if @fail_on&.match?(sql_with_params(sql, params))

        @statements << [ sql, params ]
        return @existing_keys.include?(params.first) ? [ { "present" => 1 } ] : [] if sql.start_with?("SELECT 1")

        []
      end

      def quote_identifier(name)
        %("#{name}")
      end

      def transaction
        exec("BEGIN")
        result = yield
        exec("COMMIT")
        result
      rescue StandardError => error
        exec("ROLLBACK")
        raise error
      end

      private

      def sql_with_params(sql, params)
        "#{sql} -- #{params.join(",")}"
      end
    end

    class FakeAdapter
      def initialize(session)
        @session = session
      end

      def open
        yield @session
      end
    end

    test "inserts header and line rows for a new invoice" do
      session = FakeSession.new
      result = write(session: session)

      assert_predicate result, :all_pushed?
      assert_equal "inserted", result.results.sole.operation

      inserts = session.statements.select { |sql, _| sql.start_with?("INSERT") }
      assert_equal 2, inserts.size
      header_sql, header_params = inserts.first
      assert_includes header_sql, %(INSERT INTO "customer_invoices" ("doc_ref", "inv_no", "grand_total") VALUES (?, ?, ?))
      assert_equal [ "doc_demo_global_0001", "INV-2026-1042", BigDecimal("1200.00") ], header_params

      delete_sql, delete_params = session.statements.find { |sql, _| sql.start_with?("DELETE") }
      assert_includes delete_sql, %(DELETE FROM "customer_lines")
      assert_equal [ "doc_demo_global_0001" ], delete_params

      assert_equal %w[BEGIN COMMIT], session.statements.map(&:first).select { |sql| %w[BEGIN COMMIT ROLLBACK].include?(sql) }
    end

    test "updates the header on re-push instead of duplicating" do
      session = FakeSession.new(existing_keys: [ "doc_demo_global_0001" ])
      result = write(session: session)

      assert_equal "updated", result.results.sole.operation
      update_sql, update_params = session.statements.find { |sql, _| sql.start_with?("UPDATE") }
      assert_includes update_sql, %(UPDATE "customer_invoices" SET "inv_no" = ?, "grand_total" = ? WHERE "doc_ref" = ?)
      assert_equal "doc_demo_global_0001", update_params.last
    end

    test "writes header-only when no line mapping is confirmed" do
      session = FakeSession.new
      result = write(session: session, line_mapping: false)

      assert_predicate result, :all_pushed?
      assert_empty session.statements.select { |sql, _| sql.include?("customer_lines") }
    end

    test "one failing invoice rolls back alone and the rest still push" do
      broken = revision(document_id: "doc_broken_0002")
      session = FakeSession.new(fail_on: /doc_broken_0002/)

      result = write(session: session, revisions: [ broken, revision ])

      assert_equal 1, result.pushed_count
      assert_equal 1, result.failed_count
      failed = result.results.find { |candidate| !candidate.pushed? }
      assert_equal "doc_broken_0002", failed.document_id
      assert_equal "write_failed", failed.operation
      assert_no_match(/1200|INV-2026/, failed.issues.to_json, "issues stay content-free")
      assert_includes session.statements.map(&:first), "ROLLBACK"
      assert_predicate result.results.find(&:pushed?), :pushed?
    end

    test "transform issues block SQL entirely for that invoice" do
      bad = revision(payable_amount: "not-a-number")
      session = FakeSession.new

      result = write(session: session, revisions: [ bad ])

      assert_equal 1, result.failed_count
      assert_equal "validation_failed", result.results.sole.operation
      assert_equal "unparseable_decimal", result.results.sole.issues.sole["code"]
      assert_empty session.statements, "invalid rows must never reach SQL"
    end

    test "raises without a confirmed invoices mapping" do
      connection = build_destination(confirm_header: false)

      assert_raises(InvoiceWriter::NoConfirmedMapping) do
        InvoiceWriter.call(revisions: [ revision ], connection: connection, adapter: FakeAdapter.new(FakeSession.new))
      end
    end

    private

    def invoice_attributes
      @invoice_attributes ||= JSON.parse(File.read(FIXTURE))
    end

    def revision(document_id: nil, payable_amount: nil)
      attributes = JSON.parse(JSON.generate(invoice_attributes))
      attributes["document_id"] = document_id if document_id
      attributes["totals"]["payable_amount"] = payable_amount if payable_amount
      FakeRevision.new(Canonical::Invoice.from_hash(attributes), "approved")
    end

    def build_destination(confirm_header: true, line_mapping: true)
      tenant = Tenant.create!(name: "Writer", slug: "writer-#{SecureRandom.hex(3)}")
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "warehouse", adapter: "postgresql", host: "h", port: 5432,
        database_name: "d", username: "u", password: "p", ssl_mode: "prefer",
        schema_snapshot: SNAPSHOT, schema_captured_at: Time.current
      )
      Destination::FieldMapping.create!(
        tenant: tenant, database_connection: connection, source_table: "invoices",
        target_table: "customer_invoices", status: confirm_header ? "confirmed" : "proposed",
        column_mappings: [
          { "source_column" => "document_id", "target_column" => "doc_ref" },
          { "source_column" => "invoice_number", "target_column" => "inv_no" },
          { "source_column" => "payable_amount", "target_column" => "grand_total" }
        ]
      )
      if line_mapping
        Destination::FieldMapping.create!(
          tenant: tenant, database_connection: connection, source_table: "line_items",
          target_table: "customer_lines", status: "confirmed",
          column_mappings: [
            { "source_column" => "document_id", "target_column" => "doc_ref" },
            { "source_column" => "line_id", "target_column" => "line_ref" },
            { "source_column" => "line_net_amount", "target_column" => "amount" }
          ]
        )
      end
      connection
    end

    def write(session:, revisions: [ revision ], line_mapping: true)
      connection = build_destination(line_mapping: line_mapping)
      InvoiceWriter.call(revisions: revisions, connection: connection, adapter: FakeAdapter.new(session))
    end
  end
end
