# frozen_string_literal: true

require "bigdecimal"

module Canonical
  class DecimalAmount
    PATTERN = /\A-?\d+(\.\d{1,8})?\z/

    include Comparable

    attr_reader :value

    def self.parse(input)
      new(input)
    end

    def initialize(input)
      raise ArgumentError, "decimal amount must be a string" unless input.is_a?(String)
      raise ArgumentError, "decimal amount must match #{PATTERN.inspect}" unless input.match?(PATTERN)

      @value = BigDecimal(input)
    end

    def +(other)
      self.class.send(:from_decimal, value + self.class.coerce(other).value)
    end

    def -(other)
      self.class.send(:from_decimal, value - self.class.coerce(other).value)
    end

    def <=>(other)
      value <=> self.class.coerce(other).value
    end

    def zero?
      value.zero?
    end

    def scale
      fraction = to_s.split(".", 2).last
      fraction == to_s ? 0 : fraction.length
    end

    def fits_minor_units?(currency)
      scale <= CurrencyRegistry.minor_units(currency)
    end

    def to_minor_units(currency)
      minor_units = CurrencyRegistry.minor_units(currency)
      raise ArgumentError, "#{self} exceeds #{currency} minor-unit precision" unless scale <= minor_units

      (value * (10**minor_units)).to_i
    end

    def to_s
      string = value.to_s("F")
      string = string.sub(/\.0+\z/, "")
      string = string.sub(/(\.\d*?)0+\z/, "\\1")
      string == "-0" ? "0" : string
    end

    def inspect
      "#<#{self.class.name} #{self}>"
    end

    protected

    def self.coerce(input)
      input.is_a?(self) ? input : new(input)
    end

    def self.from_decimal(decimal)
      amount = allocate
      amount.instance_variable_set(:@value, decimal)
      amount
    end
    private_class_method :from_decimal
  end
end
