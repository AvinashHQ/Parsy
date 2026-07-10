# frozen_string_literal: true

module Destinations
  class MappingsController < ApplicationController
    def propose
      connection = tenant_connections.find(params[:connection_id])
      result = Destination::MappingProposer.call(
        connection: connection,
        source_table: params.require(:source_table),
        target_table: params[:target_table].presence
      )
      notice = "Mapping proposed for #{result.mapping.source_table.humanize.downcase} → #{result.mapping.target_table}"
      notice += " (#{result.unmapped_source_columns.size} columns left unmapped)" if result.unmapped_source_columns.any?
      redirect_to edit_destinations_connection_mapping_path(connection, result.mapping), notice: notice
    rescue Destination::MappingProposer::SchemaUnknown, Destination::MappingProposer::NoTargetTable => error
      redirect_to destinations_connection_path(connection), alert: error.message
    end

    def edit
      @mapping = tenant_mappings.find(params[:id])
      @connection = @mapping.database_connection
      @report = Destination::MappingValidator.call(mapping: @mapping)
      @target_columns = target_columns_for(@mapping)
    end

    def update
      @mapping = tenant_mappings.find(params[:id])
      @connection = @mapping.database_connection
      if @mapping.update(column_mappings: submitted_entries(@mapping), origin: "operator")
        redirect_to edit_destinations_connection_mapping_path(@connection, @mapping), notice: "Mapping saved. Confirm it to enable pushes."
      else
        @report = Destination::MappingValidator.call(mapping: @mapping)
        @target_columns = target_columns_for(@mapping)
        render :edit, status: :unprocessable_entity
      end
    end

    def confirm
      mapping = tenant_mappings.find(params[:id])
      result = Destination::MappingConfirmer.call(mapping: mapping)
      if result.confirmed?
        redirect_to destinations_connection_path(mapping.database_connection),
                    notice: "Mapping confirmed for #{mapping.source_table.humanize.downcase}"
      else
        redirect_to edit_destinations_connection_mapping_path(mapping.database_connection, mapping),
                    alert: "Mapping is not valid yet: #{result.report.errors.size} blocking issues"
      end
    end

    private

    def tenant_connections
      Destination::DatabaseConnection.where(tenant: current_tenant)
    end

    def tenant_mappings
      Destination::FieldMapping.where(tenant: current_tenant, database_connection_id: params[:connection_id])
    end

    # The form posts mappings[<source_column>]=<target_column>; entries keep
    # canonical column order and blanks mean "unmapped".
    def submitted_entries(mapping)
      submitted = params[:mappings]
      Destination::SourceSchema.column_names(mapping.source_table).filter_map do |source|
        target = submitted && submitted[source]
        { "source_column" => source, "target_column" => target } if target.present?
      end
    end

    def target_columns_for(mapping)
      tables = Array(mapping.database_connection.schema_snapshot["tables"])
      table = tables.find { |candidate| candidate["name"] == mapping.target_table }
      Array(table && table["columns"])
    end
  end
end
