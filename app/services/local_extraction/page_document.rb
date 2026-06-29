# frozen_string_literal: true

module LocalExtraction
  class PageDocument
    LayoutBlock = Data.define(:id, :page_number, :kind, :bbox, :text, :confidence) do
      def to_h
        {
          id: id,
          page_number: page_number,
          kind: kind,
          bbox: bbox,
          text: text,
          confidence: confidence
        }.compact
      end
    end

    Table = Data.define(:id, :page_number, :bbox, :rows) do
      def to_h
        {
          id: id,
          page_number: page_number,
          bbox: bbox,
          rows: rows
        }.compact
      end
    end

    Evidence = Data.define(:id, :page_number, :kind, :bbox, :text, :source) do
      def to_h
        {
          id: id,
          page_number: page_number,
          kind: kind,
          bbox: bbox,
          text: text,
          source: source
        }.compact
      end
    end

    Page = Data.define(:number, :width, :height, :rotation, :layout, :tables, :evidence, :quality_warnings) do
      def to_h
        {
          number: number,
          width: width,
          height: height,
          rotation: rotation,
          layout: layout.map(&:to_h),
          tables: tables.map(&:to_h),
          evidence: evidence.map(&:to_h),
          quality_warnings: quality_warnings
        }.compact
      end
    end

    Result = Data.define(:status, :document, :error_code, :warnings, :metadata) do
      def accepted? = status == :accepted
      def failed? = status == :failed

      def observability
        {
          status: status.to_s,
          error_code: error_code,
          page_count: document&.pages&.length,
          warning_codes: warnings,
          metadata: metadata
        }.compact
      end

      def to_h
        {
          status: status.to_s,
          document: document&.to_h,
          error_code: error_code,
          warnings: warnings,
          metadata: metadata
        }.compact
      end
    end

    attr_reader :pages, :source_type, :metadata

    def initialize(pages:, source_type:, metadata: {})
      @pages = Array(pages).freeze
      @source_type = source_type.to_s.freeze
      @metadata = self.class.send(:deep_symbolize, metadata).freeze
      freeze
    end

    def self.accepted(pages:, source_type:, metadata:, warnings: [])
      document = new(pages:, source_type:, metadata:)
      Result.new(status: :accepted, document:, error_code: nil, warnings: normalize_codes(warnings), metadata: document.metadata)
    end

    def self.failed(error_code:, metadata:, warnings: [])
      Result.new(status: :failed, document: nil, error_code: error_code.to_s, warnings: normalize_codes(warnings), metadata: deep_symbolize(metadata).freeze)
    end

    def self.page(number:, width:, height:, rotation: 0, layout: [], tables: [], evidence: [], quality_warnings: [])
      Page.new(
        number: Integer(number),
        width: numeric_or_nil(width),
        height: numeric_or_nil(height),
        rotation: Integer(rotation || 0),
        layout: Array(layout).map { |block| layout_block(block, page_number: number) }.freeze,
        tables: Array(tables).map { |table| table(table, page_number: number) }.freeze,
        evidence: Array(evidence).map { |item| evidence(item, page_number: number) }.freeze,
        quality_warnings: normalize_codes(quality_warnings)
      )
    end

    def self.layout_block(value, page_number:)
      attributes = normalize_hash(value)
      LayoutBlock.new(
        id: attributes.fetch(:id) { "p#{page_number}-b1" }.to_s,
        page_number: Integer(attributes.fetch(:page_number, page_number)),
        kind: attributes.fetch(:kind, "text").to_s,
        bbox: normalize_bbox(attributes[:bbox]),
        text: attributes[:text].to_s,
        confidence: numeric_or_nil(attributes[:confidence])
      )
    end

    def self.table(value, page_number:)
      attributes = normalize_hash(value)
      Table.new(
        id: attributes.fetch(:id) { "p#{page_number}-t1" }.to_s,
        page_number: Integer(attributes.fetch(:page_number, page_number)),
        bbox: normalize_bbox(attributes[:bbox]),
        rows: Array(attributes[:rows]).map { |row| Array(row).map(&:to_s).freeze }.freeze
      )
    end

    def self.evidence(value, page_number:)
      attributes = normalize_hash(value)
      Evidence.new(
        id: attributes.fetch(:id) { "p#{page_number}-e1" }.to_s,
        page_number: Integer(attributes.fetch(:page_number, page_number)),
        kind: attributes.fetch(:kind, "text").to_s,
        bbox: normalize_bbox(attributes[:bbox]),
        text: attributes[:text].to_s,
        source: attributes.fetch(:source, "local_extraction").to_s
      )
    end

    def self.normalize_codes(values)
      Array(values).compact.map { |value| value.to_s.upcase }.uniq.sort.freeze
    end

    def to_h
      {
        source_type: source_type,
        pages: pages.map(&:to_h),
        metadata: metadata
      }
    end

    def observability
      {
        source_type: source_type,
        page_count: pages.length,
        warning_codes: pages.flat_map(&:quality_warnings).uniq.sort,
        metadata: metadata
      }
    end

    def self.normalize_hash(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_sym] = item }
      else
        {}
      end
    end

    def self.normalize_bbox(value)
      coordinates = Array(value || [ 0, 0, 0, 0 ]).first(4).map { |coordinate| numeric_or_nil(coordinate) || 0 }
      coordinates.fill(0, coordinates.length...4).freeze
    end

    def self.numeric_or_nil(value)
      return nil if value.nil?

      number = Float(value)
      number == number.to_i ? number.to_i : number
    rescue ArgumentError, TypeError
      nil
    end

    def self.deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_sym] = deep_symbolize(item) }
      when Array
        value.map { |item| deep_symbolize(item) }.freeze
      else
        value
      end
    end

    private_class_method :normalize_hash, :normalize_bbox, :numeric_or_nil, :deep_symbolize
  end
end
