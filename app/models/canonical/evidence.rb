# frozen_string_literal: true

module Canonical
  class Evidence < ValueObject
    def field_path = value(:field_path)
    def source_kind = value(:source_kind)
    def page = value(:page)
    def source_path = value(:source_path)
    def text = value(:text)
    def bbox = value(:bbox)
  end
end
