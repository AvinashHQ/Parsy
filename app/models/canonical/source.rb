# frozen_string_literal: true

module Canonical
  class Source < ValueObject
    def family = value(:family)
    def route = value(:route)
    def mime_type = value(:mime_type)
    def profile = value(:profile)
    def profile_version = value(:profile_version)
    def page_count = value(:page_count)
    def has_embedded_structured_data = value(:has_embedded_structured_data)
  end
end
