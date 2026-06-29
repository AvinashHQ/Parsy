# frozen_string_literal: true

module Security
  class PrivacyLaunchVerifier
    Result = Data.define(:approved, :missing)

    REQUIRED_FLAGS = %w[deletion_verified logging_verified restore_verified tenant_isolation_verified cost_controls_verified].freeze

    def self.call(tenant:)
      new(tenant:).call
    end

    def initialize(tenant:)
      @tenant = tenant
    end

    def call
      missing = []
      missing << "privacy_approved_at" if tenant.privacy_approved_at.blank?
      REQUIRED_FLAGS.each { |flag| missing << flag unless tenant.privacy_approval.fetch(flag, false) }
      missing << "storage_region" if tenant.storage_region.blank?
      missing << "hosting_region" if tenant.hosting_region.blank?
      Result.new(approved: missing.empty?, missing: missing)
    end

    private

    attr_reader :tenant
  end
end
