# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Destination
  # Gemini text client for schema-mapping proposals. It only ever sends schema
  # METADATA — canonical column names/kinds and the destination's table/column
  # names/types — never invoice content and never credentials (ADR-027
  # disclosure posture; egress is tenant-gated by MappingProposer).
  #
  # Mirrors RemoteVision::GeminiClient conventions: ENV-provided API key sent
  # via header, a `transport` seam for deterministic tests, and content-free
  # error messages.
  class MappingLlm
    PROVIDER = "google_gemini"
    DEFAULT_MODEL = "gemini-2.5-flash"
    DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com"
    DEFAULT_API_VERSION = "v1beta"

    class ProposalError < StandardError; end

    def initialize(api_key: ENV["GEMINI_API_KEY"].presence,
                   model: ENV["PARSY_GEMINI_MODEL"].presence || DEFAULT_MODEL,
                   base_url: ENV.fetch("PARSY_GEMINI_URL", DEFAULT_BASE_URL),
                   api_version: ENV.fetch("PARSY_GEMINI_API_VERSION", DEFAULT_API_VERSION),
                   transport: nil,
                   open_timeout: 5,
                   read_timeout: 30)
      @api_key = api_key
      @model = model
      @base_url = base_url.to_s.chomp("/")
      @api_version = api_version
      @transport = transport
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def enabled?
      !@api_key.nil?
    end

    # source_columns: [{ name:, kind: }], target_columns: [{ name:, data_type: }].
    # Returns { source_column_name => target_column_name } for confident matches
    # only; target names outside the given list are dropped.
    def propose(source_table:, source_columns:, target_table:, target_columns:)
      raise ProposalError, "mapping llm is not configured" unless enabled?

      body = JSON.generate(request_body(source_table:, source_columns:, target_table:, target_columns:))
      payload = post_generate(body)
      allowed = target_columns.map { |column| column[:name] || column["name"] }
      parse_proposal(payload).select { |_source, target| allowed.include?(target) }
    end

    private

    def request_body(source_table:, source_columns:, target_table:, target_columns:)
      {
        contents: [ { role: "user", parts: [ { text: prompt(source_table:, source_columns:, target_table:, target_columns:) } ] } ],
        generationConfig: { temperature: 0, responseMimeType: "application/json" }
      }
    end

    def prompt(source_table:, source_columns:, target_table:, target_columns:)
      source_list = source_columns.map { |column| "- #{column[:name] || column["name"]} (#{column[:kind] || column["kind"]})" }.join("\n")
      target_list = target_columns.map { |column| "- #{column[:name] || column["name"]} (#{column[:data_type] || column["data_type"]})" }.join("\n")

      <<~PROMPT
        You map columns between two relational database schemas for invoice data.

        Source table "#{source_table}" (canonical invoice export) columns:
        #{source_list}

        Target table "#{target_table}" (customer database) columns:
        #{target_list}

        Return a JSON object whose keys are source column names and values are the
        best-matching target column names. Use only target columns from the list.
        Match on semantic meaning, not just name similarity. Map each target column
        at most once. Omit source columns that have no confident match. Return {}
        if nothing matches confidently.
      PROMPT
    end

    def parse_proposal(payload)
      text = payload.dig("candidates", 0, "content", "parts", 0, "text").to_s
      parsed = JSON.parse(text)
      raise ProposalError, "mapping llm returned a non-object proposal" unless parsed.is_a?(Hash)

      parsed.select { |source, target| source.is_a?(String) && target.is_a?(String) }
    rescue JSON::ParserError
      raise ProposalError, "mapping llm returned invalid JSON"
    end

    def post_generate(body)
      uri = URI.join("#{@base_url}/", "#{@api_version}/", "models/#{@model}:generateContent")
      status, response_body = perform_request(uri:, body:)
      raise ProposalError, "mapping llm returned HTTP #{status}" unless (200..299).cover?(status.to_i)

      JSON.parse(response_body.to_s)
    rescue JSON::ParserError
      raise ProposalError, "mapping llm returned an unreadable response"
    rescue Errno::ECONNREFUSED, SocketError, IOError, Timeout::Error, SystemCallError => error
      raise ProposalError, "mapping llm unreachable: #{error.class}"
    end

    def perform_request(uri:, body:)
      headers = { "Content-Type" => "application/json", "x-goog-api-key" => @api_key }
      return @transport.call(uri:, headers:, body:, read_timeout: @read_timeout) if @transport

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.use_ssl = (uri.scheme == "https")

      post = Net::HTTP::Post.new(uri)
      headers.each { |key, value| post[key] = value }
      post.body = body

      response = http.request(post)
      [ response.code.to_i, response.body.to_s ]
    end
  end
end
