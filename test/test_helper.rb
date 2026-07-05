ENV["RAILS_ENV"] ||= "test"

if ENV["COVERAGE"] == "true"
  require "simplecov"

  SimpleCov.start "rails" do
    enable_coverage :branch
    minimum_coverage line: 90

    add_group "Services", "app/services"
    add_group "Value Objects", "app/models/canonical"
  end
end
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: ENV["COVERAGE"] == "true" ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
