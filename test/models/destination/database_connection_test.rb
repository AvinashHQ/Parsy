# frozen_string_literal: true

require "test_helper"

module Destination
  class DatabaseConnectionTest < ActiveSupport::TestCase
    test "valid with an allowlisted adapter" do
      connection = build_connection(tenant: create_tenant!)

      assert_predicate connection, :valid?
    end

    test "rejects adapters outside the allowlist" do
      tenant = create_tenant!

      %w[sqlite3 sqlserver oracle mysql2].each do |adapter|
        connection = build_connection(tenant: tenant, adapter: adapter)

        assert_not connection.valid?, "expected #{adapter} to be rejected"
        assert_includes connection.errors[:adapter], "is not included in the list"
      end
    end

    test "rejects invalid ssl modes and out-of-range ports" do
      tenant = create_tenant!

      assert_not build_connection(tenant: tenant, ssl_mode: "verify-full").valid?
      assert_not build_connection(tenant: tenant, port: 0).valid?
      assert_not build_connection(tenant: tenant, port: 65_536).valid?
    end

    test "label is unique within a tenant but reusable across tenants" do
      tenant = create_tenant!
      other_tenant = create_tenant!(slug: "other-tenant")
      build_connection(tenant: tenant, label: "warehouse").save!

      duplicate = build_connection(tenant: tenant, label: "warehouse")
      cross_tenant = build_connection(tenant: other_tenant, label: "warehouse")

      assert_not duplicate.valid?
      assert_predicate cross_tenant, :valid?
    end

    test "encrypts credentials at rest" do
      connection = build_connection(tenant: create_tenant!)
      connection.save!

      raw = ActiveRecord::Base.connection.select_one(
        "SELECT username, password FROM destination_database_connections WHERE id = #{connection.id}"
      )

      assert_not_equal "warehouse_writer", raw["username"]
      assert_not_equal "s3cret-value", raw["password"]
      assert_equal "warehouse_writer", connection.reload.username
      assert_equal "s3cret-value", connection.password
    end

    test "filters credentials from inspect and excludes them from serialization" do
      connection = build_connection(tenant: create_tenant!)
      connection.save!

      assert_no_match(/s3cret-value/, connection.inspect)
      assert_no_match(/warehouse_writer/, connection.inspect)

      serialized = connection.as_json
      assert_not serialized.key?("username")
      assert_not serialized.key?("password")

      with_options = connection.serializable_hash(only: %i[label username password])
      assert_equal [ "label" ], with_options.keys
    end

    test "schema_known? reflects a captured snapshot" do
      connection = build_connection(tenant: create_tenant!)

      assert_not connection.schema_known?

      connection.schema_snapshot = { "tables" => [] }
      assert_not connection.schema_known?

      connection.schema_snapshot = { "tables" => [ { "name" => "invoices", "columns" => [] } ] }
      assert_predicate connection, :schema_known?
    end

    test "destroying a tenant removes its destination connections" do
      tenant = create_tenant!
      build_connection(tenant: tenant).save!

      assert_difference -> { Destination::DatabaseConnection.count }, -1 do
        tenant.destroy!
      end
    end

    private

    def create_tenant!(slug: "dest-tenant")
      Tenant.create!(
        name: slug.titleize,
        slug: slug,
        hosting_region: "local",
        storage_region: "local"
      )
    end

    def build_connection(tenant:, label: "primary-warehouse", adapter: "postgresql", ssl_mode: "prefer", port: 5432)
      Destination::DatabaseConnection.new(
        tenant: tenant,
        label: label,
        adapter: adapter,
        host: "db.customer.example",
        port: port,
        database_name: "erp",
        username: "warehouse_writer",
        password: "s3cret-value",
        ssl_mode: ssl_mode
      )
    end
  end
end
