# frozen_string_literal: true

require "test_helper"

module Security
  class PrivacyLaunchVerifierTest < ActiveSupport::TestCase
    test "privacy launch requires signed evidence flags" do
      tenant = Tenant.create!(name: "Privacy", slug: "privacy")
      missing = Security::PrivacyLaunchVerifier.call(tenant:)

      assert_not missing.approved
      assert_includes missing.missing, "privacy_approved_at"
      assert_includes missing.missing, "deletion_verified"

      tenant.update!(
        privacy_approved_at: Time.current,
        privacy_approved_by: "dpo@example.test",
        privacy_approval: {
          deletion_verified: true,
          logging_verified: true,
          restore_verified: true,
          tenant_isolation_verified: true,
          cost_controls_verified: true
        }
      )

      assert Security::PrivacyLaunchVerifier.call(tenant:).approved
    end
  end
end
