# frozen_string_literal: true

module Canonical
  class ValueObject
    attr_reader :attributes

    def self.from_hash(attributes)
      new(attributes)
    end

    def self.wrap_many(klass, values)
      Array(values).map { |attributes| klass.new(attributes) }
    end

    def initialize(attributes)
      @attributes = self.class.deep_freeze(attributes.deep_stringify_keys)
    end

    def [](key)
      attributes[key.to_s]
    end

    def to_h
      attributes.deep_dup
    end

    def ==(other)
      other.is_a?(self.class) && other.to_h == to_h
    end

    protected

    def value(key)
      attributes[key.to_s]
    end

    def object(key, klass)
      attributes = value(key)
      attributes.nil? ? nil : klass.new(attributes)
    end

    def objects(key, klass)
      self.class.wrap_many(klass, value(key))
    end

    def self.deep_freeze(object)
      case object
      when Hash
        object.each_value { |item| deep_freeze(item) }.freeze
      when Array
        object.each { |item| deep_freeze(item) }.freeze
      else
        object.freeze
      end
    end
  end
end
