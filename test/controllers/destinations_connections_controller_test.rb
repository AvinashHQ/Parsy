# frozen_string_literal: true

require "test_helper"

class DestinationsConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # allowed_providers excludes google_gemini so no test ever reaches the cloud.
    @tenant = Tenant.create!(name: "Dest Alpha", slug: "dest-alpha", allowed_providers: [ "fixture" ])
    @other_tenant = Tenant.create!(name: "Dest Beta", slug: "dest-beta", allowed_providers: [ "fixture" ])
    @user = User.create!(tenant: @tenant, email: "dest@example.test", name: "Dest User", operator_token: "dest-token")
    @other_connection = create_connection!(tenant: @other_tenant, label: "beta-warehouse")
    post session_path, params: { email: @user.email, operator_token: "dest-token" }
  end

  test "requires authentication" do
    delete session_path
    get destinations_connections_path

    assert_redirected_to new_session_path
  end

  test "index lists only the tenant's destinations" do
    connection = create_connection!(tenant: @tenant, label: "alpha-warehouse")

    get destinations_connections_path

    assert_response :success
    assert_includes response.body, connection.label
    refute_includes response.body, @other_connection.label
  end

  test "create saves a destination without echoing credentials" do
    assert_difference -> { Destination::DatabaseConnection.count }, 1 do
      post destinations_connections_path, params: { destination_database_connection: {
        label: "erp", adapter: "postgresql", host: "db.example", port: 5432,
        database_name: "erp", username: "writer", password: "secret-value", ssl_mode: "prefer"
      } }
    end

    connection = Destination::DatabaseConnection.last
    assert_equal @tenant, connection.tenant
    assert_redirected_to destinations_connection_path(connection)

    follow_redirect!
    refute_includes response.body, "secret-value"
    refute_includes response.body, "writer"
  end

  test "create re-renders with validation errors" do
    post destinations_connections_path, params: { destination_database_connection: {
      label: "", adapter: "sqlserver", host: "db.example", port: 5432,
      database_name: "erp", username: "writer", password: "x", ssl_mode: "prefer"
    } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Could not save this destination"
  end

  test "update keeps stored credentials when the fields are left blank" do
    connection = create_connection!(tenant: @tenant, label: "keep-creds")

    patch destinations_connection_path(connection), params: { destination_database_connection: {
      label: "keep-creds-renamed", adapter: connection.adapter, host: connection.host, port: connection.port,
      database_name: connection.database_name, username: "", password: "", ssl_mode: connection.ssl_mode
    } }

    connection.reload
    assert_equal "keep-creds-renamed", connection.label
    assert_equal "writer", connection.username
    assert_equal "secret-value", connection.password
  end

  test "cross-tenant access fails closed" do
    get destinations_connection_path(@other_connection)
    assert_response :not_found

    patch destinations_connection_path(@other_connection), params: { destination_database_connection: { label: "stolen" } }
    assert_response :not_found

    delete destinations_connection_path(@other_connection)
    assert_response :not_found
    assert Destination::DatabaseConnection.exists?(@other_connection.id)

    post test_destinations_connection_path(@other_connection)
    assert_response :not_found
  end

  test "test action reports success against a live database" do
    connection = create_live_connection!(label: "live-test")

    post test_destinations_connection_path(connection)

    assert_redirected_to destinations_connection_path(connection)
    follow_redirect!
    assert_includes response.body, "Connection succeeded"
  end

  test "test action reports a content-free failure for unreachable hosts" do
    connection = create_connection!(tenant: @tenant, label: "unreachable", host: "127.0.0.1", port: 1)

    post test_destinations_connection_path(connection)

    assert_redirected_to destinations_connection_path(connection)
    follow_redirect!
    assert_includes response.body, "Connection failed"
    refute_includes response.body, "secret-value"
  end

  test "refresh_schema captures and renders the schema browser" do
    connection = create_live_connection!(label: "live-schema")

    post refresh_schema_destinations_connection_path(connection)

    assert_redirected_to destinations_connection_path(connection)
    assert_predicate connection.reload.schema_captured_at, :present?

    follow_redirect!
    assert_includes response.body, "Schema browser"
    assert_includes response.body, "tenants", "snapshot should list real tables"
  end

  test "destroy removes the destination" do
    connection = create_connection!(tenant: @tenant, label: "goner")

    assert_difference -> { Destination::DatabaseConnection.count }, -1 do
      delete destinations_connection_path(connection)
    end
    assert_redirected_to destinations_connections_path
  end

  private

  def create_connection!(tenant:, label:, host: "db.customer.example", port: 5432)
    Destination::DatabaseConnection.create!(
      tenant: tenant, label: label, adapter: "postgresql", host: host, port: port,
      database_name: "erp", username: "writer", password: "secret-value", ssl_mode: "prefer"
    )
  end

  # Points at the app's own test database so adapter round-trips are real.
  def create_live_connection!(label:)
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    Destination::DatabaseConnection.create!(
      tenant: @tenant, label: label, adapter: "postgresql",
      host: config[:host] || "localhost", port: config[:port] || 5432,
      database_name: config[:database], username: config[:username] || ENV["USER"],
      password: config[:password].to_s, ssl_mode: "prefer"
    )
  end
end
