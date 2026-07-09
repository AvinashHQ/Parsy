# frozen_string_literal: true

require "test_helper"

module Destination
  class MappingLlmTest < ActiveSupport::TestCase
    class RecordingTransport
      attr_reader :requests

      def initialize(status: 200, body: nil, error: nil)
        @status = status
        @body = body || self.class.gemini_body({ "document_id" => "doc_ref" })
        @error = error
        @requests = []
      end

      def self.gemini_body(proposal)
        JSON.generate({ "candidates" => [ { "content" => { "parts" => [ { "text" => JSON.generate(proposal) } ] } } ] })
      end

      def call(uri:, headers:, body:, read_timeout:)
        raise @error if @error

        @requests << { uri: uri, headers: headers, body: body, read_timeout: read_timeout }
        [ @status, @body ]
      end
    end

    def arguments
      {
        source_table: "invoices",
        source_columns: [ { name: "document_id", kind: "text" }, { name: "buyer_name", kind: "text" } ],
        target_table: "inv_header",
        target_columns: [ { name: "doc_ref", data_type: "character varying" }, { name: "client", data_type: "text" } ]
      }
    end

    test "sends schema metadata only and parses the proposal" do
      transport = RecordingTransport.new(
        body: RecordingTransport.gemini_body({ "document_id" => "doc_ref", "buyer_name" => "made_up" })
      )
      llm = MappingLlm.new(api_key: "test-key", transport: transport)

      proposal = llm.propose(**arguments)

      assert_equal({ "document_id" => "doc_ref" }, proposal, "targets outside the schema list are dropped")

      request = transport.requests.first
      assert_equal "test-key", request[:headers]["x-goog-api-key"]
      body = JSON.parse(request[:body])
      prompt = body.dig("contents", 0, "parts", 0, "text")
      assert_includes prompt, "document_id"
      assert_includes prompt, "doc_ref"
      assert_includes prompt, "inv_header"
      assert_no_match(/x-goog|test-key/, prompt, "credentials never enter the prompt")
      assert_equal "application/json", body.dig("generationConfig", "responseMimeType")
    end

    test "disabled without an api key" do
      llm = MappingLlm.new(api_key: nil, transport: RecordingTransport.new)

      assert_not llm.enabled?
      assert_raises(MappingLlm::ProposalError) { llm.propose(**arguments) }
    end

    test "maps http errors, invalid json, and transport failures to ProposalError" do
      http_error = MappingLlm.new(api_key: "k", transport: RecordingTransport.new(status: 500, body: "{}"))
      assert_raises(MappingLlm::ProposalError) { http_error.propose(**arguments) }

      bad_json = MappingLlm.new(api_key: "k", transport: RecordingTransport.new(body: RecordingTransport.gemini_body("nope").sub('"nope"', "not json")))
      assert_raises(MappingLlm::ProposalError) { bad_json.propose(**arguments) }

      unreachable = MappingLlm.new(api_key: "k", transport: RecordingTransport.new(error: Errno::ECONNREFUSED.new))
      assert_raises(MappingLlm::ProposalError) { unreachable.propose(**arguments) }
    end

    test "rejects non-object proposals" do
      transport = RecordingTransport.new(body: RecordingTransport.gemini_body([ "not", "a", "hash" ]))
      llm = MappingLlm.new(api_key: "k", transport: transport)

      assert_raises(MappingLlm::ProposalError) { llm.propose(**arguments) }
    end
  end
end
