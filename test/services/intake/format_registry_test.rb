# frozen_string_literal: true

require "canonical_test_helper"

module Intake
  class FormatRegistryTest < Minitest::Test
    def test_loads_repository_registry_and_finds_supported_formats
      registry = FormatRegistry.load

      assert_equal "1.0.0", registry.version

      visual_pdf = registry.find(:visual_pdf)
      assert_equal "visual_pdf", visual_pdf.id
      assert_equal "visual_pdf", visual_pdf.family
      assert_equal [ "magic_bytes_pdf" ], visual_pdf.detection
      assert_equal "visual_model", visual_pdf.route
      assert_equal "supported", visual_pdf.mvp_status

      ubl = registry.find("oasis_ubl_invoice")
      assert_equal "ubl", ubl.family
      assert_equal [ "xml_namespace_urn_oasis_ubl_invoice" ], ubl.detection
      assert_equal "structured_parser", ubl.route
      assert_equal "experimental", ubl.mvp_status
    end

    def test_rejects_unknown_format_ids_instead_of_falling_back
      registry = FormatRegistry.load

      error = assert_raises(KeyError) { registry.find("portal_xml") }
      assert_includes error.message, "portal_xml"
    end

    def test_entries_detection_lists_and_policies_are_immutable
      registry = FormatRegistry.load
      entry = registry.find("factur_x_zugferd")

      assert_predicate registry, :frozen?
      assert_predicate registry.formats, :frozen?
      assert_predicate entry, :frozen?
      assert_predicate entry.id, :frozen?
      assert_predicate entry.detection, :frozen?
      assert_predicate entry.detection.first, :frozen?
      assert_predicate registry.unknown_structured_policy, :frozen?
      assert_predicate registry.unknown_visual_policy, :frozen?

      assert_raises(FrozenError) { registry.formats << entry }
      assert_raises(FrozenError) { entry.detection << "other_detector" }
      assert_raises(FrozenError) { registry.unknown_structured_policy << "_changed" }
      assert_raises(FrozenError) { registry.unknown_visual_policy << "_changed" }
    end

    def test_unknown_format_policies_default_when_omitted_from_registry_attributes
      registry = FormatRegistry.new(
        "version" => "2026.7",
        "formats" => [
          {
            "id" => "custom_xml",
            "family" => "structured_xml",
            "detection" => "custom_detector",
            "route" => "structured_parser",
            "mvp_status" => "experimental"
          }
        ]
      )

      assert_equal "quarantine", registry.unknown_structured_policy
      assert_equal "reject_or_operator_review", registry.unknown_visual_policy
      assert_equal [ "custom_detector" ], registry.find("custom_xml").detection
    end
  end
end
