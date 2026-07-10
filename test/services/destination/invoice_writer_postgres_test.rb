# frozen_string_literal: true

require "test_helper"
require "json"

module Destination
  # Real end-to-end write path: vendor-style scratch tables on the live test
  # PostgreSQL server, introspected schema, confirmed mappings, then push,
  # idempotent re-push, and line replacement — verified by reading rows back.
  class InvoiceWriterPostgresTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    FakeRevision = Struct.new(:invoice, :status)

    setup do
      @suffix = SecureRandom.hex(4)
      @header_table = "vendor_inv_#{@suffix}"
      @lines_table = "vendor_lines_#{@suffix}"
      adapter.open do |session|
        session.exec(<<~SQL)
          CREATE TABLE "#{@header_table}" (
            doc_ref varchar(128) NOT NULL UNIQUE,
            inv_no varchar(64),
            vendor varchar(200),
            issued_on date,
            grand_total numeric(12, 2)
          )
        SQL
        session.exec(<<~SQL)
          CREATE TABLE "#{@lines_table}" (
            doc_ref varchar(128) NOT NULL,
            line_ref varchar(64) NOT NULL,
            details text,
            amount numeric(12, 2)
          )
        SQL
      end
    end

    teardown do
      adapter.open do |session|
        session.exec("SET client_min_messages = warning")
        session.exec(%(DROP TABLE IF EXISTS "#{@header_table}"))
        session.exec(%(DROP TABLE IF EXISTS "#{@lines_table}"))
      end
    end

    test "pushes, re-pushes idempotently, and replaces lines in a real database" do
      connection = build_destination!

      result = InvoiceWriter.call(revisions: [ revision ], connection: connection, adapter: adapter)

      assert_predicate result, :all_pushed?
      assert_equal "inserted", result.results.sole.operation

      header = select_all(%(SELECT * FROM "#{@header_table}")).sole
      assert_equal "doc_demo_global_0001", header["doc_ref"]
      assert_equal "INV-2026-1042", header["inv_no"]
      assert_equal "Northstar Services Ltd", header["vendor"]
      assert_equal "2026-06-15", header["issued_on"]
      assert_equal "1200.00", header["grand_total"]

      line = select_all(%(SELECT * FROM "#{@lines_table}")).sole
      assert_equal "line_1", line["line_ref"]
      assert_equal "1000.00", line["amount"]

      # Re-push with an operator-corrected amount: update, never duplicate.
      corrected = revision(payable_amount: "1300.00")
      repush = InvoiceWriter.call(revisions: [ corrected ], connection: connection, adapter: adapter)

      assert_equal "updated", repush.results.sole.operation
      headers = select_all(%(SELECT * FROM "#{@header_table}"))
      assert_equal 1, headers.size
      assert_equal "1300.00", headers.sole["grand_total"]
      assert_equal 1, select_all(%(SELECT * FROM "#{@lines_table}")).size, "lines replaced, not appended"
    end

    test "a NOT NULL violation in the target fails that invoice content-free" do
      connection = build_destination!
      # Break the data: no document_id means the NOT NULL doc_ref cannot be fed.
      broken = revision(document_id: nil)

      result = InvoiceWriter.call(revisions: [ broken, revision ], connection: connection, adapter: adapter)

      assert_equal 1, result.pushed_count
      assert_equal 1, result.failed_count
      assert_equal 1, select_all(%(SELECT * FROM "#{@header_table}")).size
      assert_no_match(/Northstar|1200/, result.results.map(&:issues).to_json)
    end

    private

    def db_config
      ActiveRecord::Base.connection_db_config.configuration_hash
    end

    def adapter
      Adapters::Postgres.new(
        host: db_config[:host] || "localhost",
        port: db_config[:port] || 5432,
        database: db_config[:database],
        username: db_config[:username] || ENV["USER"],
        password: db_config[:password].to_s,
        ssl_mode: "prefer"
      )
    end

    def select_all(sql)
      adapter.open { |session| session.exec(sql) }
    end

    def invoice_attributes
      @invoice_attributes ||= JSON.parse(File.read(FIXTURE))
    end

    def revision(document_id: :keep, payable_amount: nil)
      attributes = JSON.parse(JSON.generate(invoice_attributes))
      attributes["document_id"] = document_id unless document_id == :keep
      attributes["totals"]["payable_amount"] = payable_amount if payable_amount
      FakeRevision.new(Canonical::Invoice.from_hash(attributes), "approved")
    end

    def build_destination!
      tenant = Tenant.create!(name: "PG Writer", slug: "pg-writer-#{@suffix}")
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "live", adapter: "postgresql",
        host: db_config[:host] || "localhost", port: db_config[:port] || 5432,
        database_name: db_config[:database], username: db_config[:username] || ENV["USER"],
        password: db_config[:password].to_s, ssl_mode: "prefer"
      )
      SchemaIntrospector.call(connection: connection, adapter: adapter)

      Destination::FieldMapping.create!(
        tenant: tenant, database_connection: connection, source_table: "invoices",
        target_table: @header_table, status: "confirmed",
        column_mappings: [
          { "source_column" => "document_id", "target_column" => "doc_ref" },
          { "source_column" => "invoice_number", "target_column" => "inv_no" },
          { "source_column" => "supplier_name", "target_column" => "vendor" },
          { "source_column" => "issue_date", "target_column" => "issued_on" },
          { "source_column" => "payable_amount", "target_column" => "grand_total" }
        ]
      )
      Destination::FieldMapping.create!(
        tenant: tenant, database_connection: connection, source_table: "line_items",
        target_table: @lines_table, status: "confirmed",
        column_mappings: [
          { "source_column" => "document_id", "target_column" => "doc_ref" },
          { "source_column" => "line_id", "target_column" => "line_ref" },
          { "source_column" => "description", "target_column" => "details" },
          { "source_column" => "line_net_amount", "target_column" => "amount" }
        ]
      )
      connection
    end
  end
end
