# frozen_string_literal: true

require "test_helper"

module Destination
  class PushTest < ActiveSupport::TestCase
    test "status transitions derive from document results" do
      push = create_push!
      push.document_results = {
        "1" => { "status" => "pushed", "operation" => "inserted" },
        "2" => { "status" => "pushed", "operation" => "updated" }
      }
      push.refresh_counts_and_status!
      assert_equal "pushed", push.status
      assert_equal 2, push.pushed_count
      assert_predicate push, :terminal?
      assert_not_nil push.finished_at

      push.document_results["3"] = { "status" => "failed", "operation" => "write_failed" }
      push.refresh_counts_and_status!
      assert_equal "partial", push.status
      assert_equal [ "3" ], push.failed_document_ids

      push.document_results = { "3" => { "status" => "failed", "operation" => "write_failed" } }
      push.refresh_counts_and_status!
      assert_equal "failed", push.status
    end

    test "empty results mean failed" do
      push = create_push!
      push.refresh_counts_and_status!

      assert_equal "failed", push.status
      assert_equal 0, push.pushed_count
    end

    test "validates status and actor" do
      push = create_push!
      assert_not push.update(status: "done")
      assert_not push.update(actor: "")
    end

    private

    def create_push!
      tenant = Tenant.create!(name: "Push", slug: "push-#{SecureRandom.hex(3)}")
      batch = Review::Batch.create!(tenant: tenant, name: "Push batch")
      connection = Destination::DatabaseConnection.create!(
        tenant: tenant, label: "warehouse", adapter: "postgresql", host: "h", port: 5432,
        database_name: "d", username: "u", password: "p", ssl_mode: "prefer"
      )
      Destination::Push.create!(tenant: tenant, batch: batch, database_connection: connection, actor: "op@example.test")
    end
  end
end
