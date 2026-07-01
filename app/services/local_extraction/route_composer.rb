# frozen_string_literal: true

module LocalExtraction
  class RouteComposer
    LOCAL_ROUTES = %w[visual_model hybrid_compare].freeze

    attr_reader :semantic_adapter

    def initialize(semantic_adapter:)
      @semantic_adapter = semantic_adapter
    end

    def call(inspection:, parser_output: {}, ocr_output: {}, images_bytes: [])
      return failure_for_inspection(inspection) unless inspection.accepted?
      return unsupported_route(inspection) unless LOCAL_ROUTES.include?(inspection.route.to_s)

      semantic_adapter.extract(inspection:, parser_output:, ocr_output:, images_bytes:)
    end

    def repair(result:, inspection:, allowed_paths:, parser_output: {}, ocr_output: {})
      semantic_adapter.repair(result:, inspection:, allowed_paths:, parser_output:, ocr_output:)
    end

    private

    def failure_for_inspection(inspection)
      code = inspection.rejection_code || inspection.detection&.quarantine_reason || SafeFailure::UNSUPPORTED_ROUTE
      status_code = inspection.quarantined? ? SafeFailure::CORRUPT_DOCUMENT : code
      failure = SafeFailure.for_code(
        status_code,
        route: inspection.route || "quarantine",
        metadata: {
          source_sha256: inspection.sha256,
          route: inspection.route,
          family: inspection.detection&.family,
          profile: inspection.detection&.profile,
          detection_version: inspection.detection&.version,
          byte_size: inspection.byte_size,
          error_code: status_code
        }
      )
      QwenSemanticAdapter::SemanticResult.new(
        status: failure.status,
        candidate: nil,
        attributes: nil,
        attempts: [],
        idempotency_key: nil,
        cached: false,
        error_code: failure.code,
        repair_attempts: 0,
        provenance: failure.metadata,
        failure: failure,
        provider_result: nil
      )
    end

    def unsupported_route(inspection)
      failure = SafeFailure.for_code(
        SafeFailure::UNSUPPORTED_ROUTE,
        route: inspection.route,
        metadata: {
          source_sha256: inspection.sha256,
          route: inspection.route,
          family: inspection.detection&.family,
          profile: inspection.detection&.profile,
          detection_version: inspection.detection&.version,
          byte_size: inspection.byte_size,
          error_code: SafeFailure::UNSUPPORTED_ROUTE
        }
      )
      QwenSemanticAdapter::SemanticResult.new(
        status: failure.status,
        candidate: nil,
        attributes: nil,
        attempts: [],
        idempotency_key: nil,
        cached: false,
        error_code: failure.code,
        repair_attempts: 0,
        provenance: failure.metadata,
        failure: failure,
        provider_result: nil
      )
    end
  end
end
