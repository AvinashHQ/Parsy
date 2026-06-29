# frozen_string_literal: true

module Canonical
  class Locale < ValueObject
    def document_language = value(:document_language)
    def script = value(:script)
    def supplier_country = value(:supplier_country)
    def buyer_country = value(:buyer_country)
    def jurisdiction_candidates = value(:jurisdiction_candidates)
    def applied_region_pack = value(:applied_region_pack)
    def applied_region_pack_id = applied_region_pack&.fetch("id", nil)
    def applied_region_pack_version = applied_region_pack&.fetch("version", nil)
  end
end
