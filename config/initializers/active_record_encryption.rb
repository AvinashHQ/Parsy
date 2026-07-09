# frozen_string_literal: true

# Parsy reads all configuration from ENV (there are no Rails encrypted
# credentials). Active Record Encryption protects destination database
# credentials at rest (ADR-027), so its keys come from ENV as well.
# Test uses fixed, obviously non-secret keys so the suite and CI never
# depend on machine-local configuration.
Rails.application.configure do
  if Rails.env.test?
    config.active_record.encryption.primary_key = "parsy-test-only-primary-key"
    config.active_record.encryption.deterministic_key = "parsy-test-only-deterministic-key"
    config.active_record.encryption.key_derivation_salt = "parsy-test-only-key-derivation-salt"
  else
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
  end
end
