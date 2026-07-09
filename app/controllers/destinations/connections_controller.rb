# frozen_string_literal: true

module Destinations
  class ConnectionsController < ApplicationController
    def index
      @connections = tenant_connections.order(:label)
    end

    def show
      @connection = tenant_connections.find(params[:id])
      @mappings = @connection.field_mappings.index_by(&:source_table)
    end

    def new
      @connection = tenant_connections.new(port: 5432, ssl_mode: "prefer", adapter: "postgresql")
    end

    def create
      @connection = tenant_connections.new(connection_params)
      if @connection.save
        redirect_to destinations_connection_path(@connection), notice: "Destination saved. Test the connection, then capture its schema."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @connection = tenant_connections.find(params[:id])
    end

    def update
      @connection = tenant_connections.find(params[:id])
      if @connection.update(update_params)
        redirect_to destinations_connection_path(@connection), notice: "Destination updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      connection = tenant_connections.find(params[:id])
      connection.destroy!
      redirect_to destinations_connections_path, notice: "Destination removed"
    end

    def test
      connection = tenant_connections.find(params[:id])
      result = Destination::ConnectionTester.call(connection:)
      if result.success?
        redirect_to destinations_connection_path(connection), notice: "Connection succeeded (#{result.latency_ms} ms)"
      else
        redirect_to destinations_connection_path(connection), alert: "Connection failed: #{result.message}"
      end
    end

    def refresh_schema
      connection = tenant_connections.find(params[:id])
      snapshot = Destination::SchemaIntrospector.call(connection:)
      redirect_to destinations_connection_path(connection),
                  notice: "Schema captured: #{snapshot.fetch("tables").size} tables"
    rescue Destination::Adapters::Error => error
      redirect_to destinations_connection_path(connection), alert: "Schema capture failed: #{error.message}"
    end

    private

    def tenant_connections
      Destination::DatabaseConnection.where(tenant: current_tenant)
    end

    def connection_params
      params.require(:destination_database_connection)
            .permit(:label, :adapter, :host, :port, :database_name, :username, :password, :ssl_mode)
    end

    # Blank credentials on edit mean "keep the stored ones" — the form never
    # renders the current secrets back.
    def update_params
      permitted = connection_params
      %i[username password].each do |credential|
        permitted = permitted.except(credential) if permitted[credential].blank?
      end
      permitted
    end
  end
end
