# frozen_string_literal: true

require "test_helper"

module Destination
  class MappingProposerTest < ActiveSupport::TestCase
    SNAPSHOT = {
      "tables" => [
        {
          "name" => "inv_header",
          "columns" => [
            { "name" => "doc_ref", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => true },
            { "name" => "inv_no", "data_type" => "character varying", "nullable" => false, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "InvoiceDate", "data_type" => "date", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "grand_total", "data_type" => "numeric", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "vendor_name", "data_type" => "character varying", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "currency", "data_type" => "character varying", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false },
            { "name" => "mystery_col", "data_type" => "character varying", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
          ]
        },
        {
          "name" => "audit_log",
          "columns" => [
            { "name" => "entry", "data_type" => "text", "nullable" => true, "default" => nil, "primary_key" => false, "unique" => false }
          ]
        }
      ]
    }.freeze

    class FakeLlm
      attr_reader :calls

      def initialize(proposal: {}, enabled: true, error: nil)
        @proposal = proposal
        @enabled = enabled
        @error = error
        @calls = []
      end

      def enabled?
        @enabled
      end

      def propose(**arguments)
        @calls << arguments
        raise @error if @error

        @proposal
      end
    end

    test "heuristics map exact, case-normalized, and synonym column names" do
      connection = create_connection!
      llm = FakeLlm.new(enabled: false)

      result = MappingProposer.call(connection: connection, source_table: "invoices", llm: llm)

      mapping = result.mapping
      assert_equal "inv_header", mapping.target_table
      assert_equal "proposed", mapping.status
      assert_equal "heuristic", mapping.origin
      assert_equal "inv_no", mapping.target_column_for("invoice_number")
      assert_equal "InvoiceDate", mapping.target_column_for("issue_date"), "synonym + case normalization"
      assert_equal "grand_total", mapping.target_column_for("payable_amount")
      assert_equal "vendor_name", mapping.target_column_for("supplier_name")
      assert_equal "currency", mapping.target_column_for("currency")
      assert_not result.used_llm
      assert_empty llm.calls
      assert_includes result.unmapped_source_columns, "document_id"
    end

    test "llm proposals fill unresolved columns when the tenant allows cloud egress" do
      connection = create_connection!
      llm = FakeLlm.new(proposal: { "document_id" => "doc_ref", "buyer_name" => "not_a_real_column", "invoice_number" => "mystery_col" })

      result = MappingProposer.call(connection: connection, source_table: "invoices", llm: llm)

      mapping = result.mapping
      assert result.used_llm
      assert_equal "llm", mapping.origin
      assert_equal "doc_ref", mapping.target_column_for("document_id")
      assert_equal "inv_no", mapping.target_column_for("invoice_number"), "llm must not override heuristic matches"
      assert_nil mapping.target_column_for("buyer_name"), "unknown llm targets are dropped"

      call = llm.calls.first
      assert_equal "invoices", call[:source_table]
      assert_not_includes call[:source_columns].map { |column| column[:name] }, "invoice_number",
                          "only unresolved columns go to the llm"
      assert(call[:target_columns].all? { |column| column.key?(:name) && column.key?(:data_type) })
    end

    test "llm failure degrades to the heuristic-only proposal" do
      connection = create_connection!
      llm = FakeLlm.new(error: MappingLlm::ProposalError.new("mapping llm returned HTTP 500"))

      result = MappingProposer.call(connection: connection, source_table: "invoices", llm: llm)

      assert_not result.used_llm
      assert_equal "heuristic", result.mapping.origin
      assert_equal "inv_no", result.mapping.target_column_for("invoice_number")
    end

    test "tenant gating skips the llm when the provider is not allowed or the breaker is open" do
      connection = create_connection!(allowed_providers: [ "fixture" ])
      llm = FakeLlm.new(proposal: { "document_id" => "doc_ref" })

      MappingProposer.call(connection: connection, source_table: "invoices", llm: llm)
      assert_empty llm.calls

      connection.tenant.update!(allowed_providers: [], circuit_breaker_status: "open")
      MappingProposer.call(connection: connection, source_table: "invoices", llm: llm)
      assert_empty llm.calls
    end

    test "re-proposing updates the existing mapping row" do
      connection = create_connection!
      llm = FakeLlm.new(enabled: false)

      first = MappingProposer.call(connection: connection, source_table: "invoices", llm: llm).mapping
      first.update!(status: "confirmed")
      second = MappingProposer.call(connection: connection, source_table: "invoices", llm: llm).mapping

      assert_equal first.id, second.id
      assert_equal "proposed", second.status
    end

    test "explicit target table overrides the automatic pick" do
      connection = create_connection!
      llm = FakeLlm.new(enabled: false)

      result = MappingProposer.call(connection: connection, source_table: "invoices", target_table: "audit_log", llm: llm)

      assert_equal "audit_log", result.mapping.target_table
      assert_not_predicate result.report, :valid?
    end

    test "raises when the schema has not been introspected or nothing resembles the source" do
      connection = create_connection!(snapshot: {})
      assert_raises(MappingProposer::SchemaUnknown) do
        MappingProposer.call(connection: connection, source_table: "invoices", llm: FakeLlm.new(enabled: false))
      end

      no_match = create_connection!(slug: "prop-nomatch", snapshot: { "tables" => [ { "name" => "unrelated", "columns" => [] } ] })
      assert_raises(MappingProposer::NoTargetTable) do
        MappingProposer.call(connection: no_match, source_table: "invoices", llm: FakeLlm.new(enabled: false))
      end
    end

    test "rejects unknown source tables" do
      assert_raises(ArgumentError) do
        MappingProposer.call(connection: create_connection!, source_table: "parties", llm: FakeLlm.new(enabled: false))
      end
    end

    private

    def create_connection!(slug: "prop-#{SecureRandom.hex(3)}", snapshot: SNAPSHOT, allowed_providers: [])
      tenant = Tenant.create!(
        name: slug.titleize, slug: slug, hosting_region: "local", storage_region: "local",
        allowed_providers: allowed_providers
      )
      Destination::DatabaseConnection.create!(
        tenant: tenant, label: "warehouse", adapter: "postgresql",
        host: "db.customer.example", port: 5432, database_name: "erp",
        username: "writer", password: "secret", ssl_mode: "prefer",
        schema_snapshot: snapshot, schema_captured_at: snapshot.present? ? Time.current : nil
      )
    end
  end
end
