# frozen_string_literal: true

require "test_helper"
require "json"

module Destination
  # End-to-end job coverage against the live test PostgreSQL server: approved
  # documents land as rows, results/provenance are recorded, and retry merges.
  class PushBatchJobTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/canonical/fix_005_generic_vat_eur.json")

    setup do
      @suffix = SecureRandom.hex(4)
      @header_table = "job_inv_#{@suffix}"
      adapter.open do |session|
        session.exec(<<~SQL)
          CREATE TABLE "#{@header_table}" (
            doc_ref varchar(128) NOT NULL UNIQUE,
            inv_no varchar(64),
            grand_total numeric(12, 2)
          )
        SQL
      end
    end

    teardown do
      adapter.open do |session|
        session.exec("SET client_min_messages = warning")
        session.exec(%(DROP TABLE IF EXISTS "#{@header_table}"))
      end
    end

    test "pushes approved documents, records provenance, and skips unapproved ones" do
      tenant, batch, document = create_reviewed_batch!
      create_unapproved_document!(batch)
      connection = create_destination!(tenant)
      push = Destination::Push.create!(tenant: tenant, batch: batch, database_connection: connection, actor: "op@example.test")

      PushBatchJob.perform_now(push.id)

      push.reload
      assert_equal "pushed", push.status
      assert_equal 1, push.pushed_count
      assert_equal 0, push.failed_count
      assert_not_nil push.started_at
      assert_not_nil push.finished_at

      result = push.document_results.fetch(document.id.to_s)
      assert_equal "inserted", result["operation"]
      assert_equal "doc_demo_global_0001", result["canonical_document_id"]

      rows = adapter.open { |session| session.exec(%(SELECT * FROM "#{@header_table}")) }
      assert_equal 1, rows.size, "only the approved document may be written"
      assert_equal "INV-2026-1042", rows.sole["inv_no"]

      event = batch.events.order(:id).last
      assert_equal "database_push_completed", event.action
      assert_equal "pushed", event.metadata["status"]
      assert_no_match(/INV-2026|Northstar|1200/, event.metadata.to_json, "provenance stays content-free")
    end

    test "missing confirmed mapping fails the push with a content-free reason" do
      tenant, batch, _document = create_reviewed_batch!
      connection = create_destination!(tenant, confirm: false)
      push = Destination::Push.create!(tenant: tenant, batch: batch, database_connection: connection, actor: "op@example.test")

      PushBatchJob.perform_now(push.id)

      push.reload
      assert_equal "failed", push.status
      assert_includes push.failure_reason, "no confirmed invoices mapping"
    end

    test "unreachable destination fails the push instead of raising" do
      tenant, batch, _document = create_reviewed_batch!
      connection = create_destination!(tenant)
      connection.update!(host: "127.0.0.1", port: 1)
      push = Destination::Push.create!(tenant: tenant, batch: batch, database_connection: connection, actor: "op@example.test")

      PushBatchJob.perform_now(push.id)

      assert_equal "failed", push.reload.status
      assert_includes push.failure_reason, "destination connection failed"
    end

    private

    def db_config
      ActiveRecord::Base.connection_db_config.configuration_hash
    end

    def adapter
      Adapters::Postgres.new(
        host: db_config[:host] || "localhost", port: db_config[:port] || 5432,
        database: db_config[:database], username: db_config[:username] || ENV["USER"],
        password: db_config[:password].to_s, ssl_mode: "prefer"
      )
    end

    def create_reviewed_batch!
      tenant = Tenant.create!(name: "Job", slug: "job-#{@suffix}")
      batch = Review::Batch.create!(tenant: tenant, name: "Job batch")
      document = ingest_document!(batch, "job-sha-#{@suffix}")
      Review::ApprovalService.call(revision: document.current_revision, actor: "op@example.test")
      [ tenant, batch, document.reload ]
    end

    def create_unapproved_document!(batch)
      attributes = JSON.parse(FIXTURE.read)
      attributes["document_id"] = "doc_unapproved_#{@suffix}"
      ingest_document!(batch, "job-unapproved-#{@suffix}", attributes: attributes)
    end

    def ingest_document!(batch, source_sha, attributes: JSON.parse(FIXTURE.read))
      attributes["evidence"] += [
        { "field_path" => "/supplier/display_name", "source_kind" => "visual", "page" => 1, "text" => "Northstar Services Ltd", "source_path" => nil, "bbox" => nil },
        { "field_path" => "/invoice/currency", "source_kind" => "visual", "page" => 1, "text" => "EUR", "source_path" => nil, "bbox" => nil }
      ]
      invoice = Canonical::Invoice.from_hash(attributes)
      attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
        schema_version: "2.0", route: "visual_model", region: "global_generic_v1", provider: "fixture",
        provider_version: "m4", model: "fixture", model_version: "m4", prompt_sha256: "abc123", latency_ms: 1, repair_attempt: 0
      )
      result = Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) { def success? = true }
                     .new(candidate: invoice, attempts: [ attempt ], idempotency_key: SecureRandom.hex(8))
      Review::ProviderResultIngester.call(batch:, source_sha256: source_sha, result:, source_metadata: { safe_preview_path: "preview://#{source_sha}" })
    end

    def create_destination!(tenant, confirm: true)
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "live", adapter: "postgresql",
        host: db_config[:host] || "localhost", port: db_config[:port] || 5432,
        database_name: db_config[:database], username: db_config[:username] || ENV["USER"],
        password: db_config[:password].to_s, ssl_mode: "prefer"
      )
      SchemaIntrospector.call(connection: connection, adapter: adapter)
      Destination::FieldMapping.create!(
        tenant: tenant, database_connection: connection, source_table: "invoices",
        target_table: @header_table, status: confirm ? "confirmed" : "proposed",
        column_mappings: [
          { "source_column" => "document_id", "target_column" => "doc_ref" },
          { "source_column" => "invoice_number", "target_column" => "inv_no" },
          { "source_column" => "payable_amount", "target_column" => "grand_total" }
        ]
      )
      connection
    end
  end
end
