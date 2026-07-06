# frozen_string_literal: true

require "test_helper"
require "yaml"

class ProductionSecurityConfigTest < ActiveSupport::TestCase
  test "production uses private object storage and ssl" do
    production = Rails.root.join("config/environments/production.rb").read

    assert_includes production, 'config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "amazon").to_sym'
    assert_includes production, 'config.assume_ssl = ENV.fetch("FORCE_SSL", "true") == "true"'
    assert_includes production, 'config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"'
    assert_includes production, "config.hosts = ENV.fetch"
  end

  test "deploy config separates web and job roles with private storage secrets" do
    deploy = Rails.root.join("config/deploy.yml").read

    assert_match(/^  job:/, deploy)
    assert_includes deploy, "cmd: bin/jobs"
    assert_includes deploy, "SOLID_QUEUE_IN_PUMA: false"
    assert_includes deploy, "PRIVATE_STORAGE_BUCKET"
    assert_includes deploy, "AWS_SECRET_ACCESS_KEY"
  end

  test "ci runs security scanners and system tests" do
    ci = Rails.root.join("config/ci.rb").read

    assert_includes ci, "bin/bundler-audit"
    assert_includes ci, "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    assert_includes ci, "bin/rails test:system"
  end
end
