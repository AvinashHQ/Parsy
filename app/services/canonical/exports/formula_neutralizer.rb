# frozen_string_literal: true

module Canonical
  module Exports
    class FormulaNeutralizer
      DANGEROUS_PREFIX = /\A[=+\-@]/

      def self.neutralize(value, trusted: false)
        return value unless value.is_a?(String)
        return value if trusted || !value.match?(DANGEROUS_PREFIX)

        "'#{value}"
      end
    end
  end
end
