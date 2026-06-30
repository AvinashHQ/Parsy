# frozen_string_literal: true

require "digest"
require "stringio"
require "zip"

module Intake
  class OperatorUpload
    Result = Data.define(:batch, :entries, :archive_error) do
      def flash_message
        if batch.present?
          "Uploaded #{persisted_count} #{'document'.pluralize(persisted_count)} to #{batch.name}: #{candidate_ready_count} ready for review, #{queued_without_candidate_count} awaiting extraction, #{quarantined_count} quarantined, #{rejected_count} rejected, #{duplicate_count} duplicate."
        else
          "No invoice files were uploaded: #{rejected_count} rejected. #{archive_error || 'No supported invoice files were found.'}"
        end
      end

      private

      def persisted_count = entries.count(&:persisted?)
      def candidate_ready_count = entries.count(&:candidate_ready?)
      def queued_without_candidate_count = entries.count(&:queued_without_candidate?)
      def quarantined_count = entries.count(&:quarantined?)
      def rejected_count = entries.count(&:rejected?)
      def duplicate_count = entries.count(&:duplicate?)
    end

    EntryResult = Data.define(:status, :sha256, :route, :document, :rejection_code, :message) do
      def persisted? = document.present? && !duplicate?
      def candidate_ready? = !duplicate? && document&.current_revision_id.present?
      def queued_without_candidate? = !duplicate? && document.present? && document.current_revision_id.blank? && document.status == "needs_review"
      def quarantined? = status == "quarantined"
      def rejected? = status == "rejected"
      def duplicate? = status == "duplicate"
    end

    StructuredPersistenceResult = Data.define(:candidate, :idempotency_key, :provenance, :error_code) do
      def success? = candidate.present?
      def attempts = []
    end

    class InvalidUpload < StandardError; end

    MAX_ARCHIVE_BYTES = Intake::UploadInspector::DEFAULT_MAX_BYTES
    MAX_ZIP_ENTRY_BYTES = Intake::UploadInspector::DEFAULT_MAX_BYTES
    MAX_ZIP_ENTRIES = 50
    MAX_ZIP_UNCOMPRESSED_BYTES = 100.megabytes

    def self.call(tenant:, actor:, upload:, batch_name: nil)
      new(tenant:, actor:, upload:, batch_name:).call
    end

    def initialize(tenant:, actor:, upload:, batch_name: nil, inspector: Intake::UploadInspector.new, structured_adapter: Intake::StructuredInvoiceAdapter.new)
      @tenant = tenant
      @actor = actor
      @upload = upload
      @batch_name = batch_name.to_s.strip.presence
      @inspector = inspector
      @structured_adapter = structured_adapter
      @batch = nil
      @processed_documents_by_sha = {}
      @zip_upload = false
    end

    def call
      raise InvalidUpload, "Choose an invoice or ZIP file to upload" if upload.blank?

      bytes = read_upload_bytes
      @zip_upload = zip_archive?(bytes)
      entries = if zip_upload?
        process_zip(bytes, original_filename: upload.original_filename.to_s)
      else
        [ process_entry(filename: upload.original_filename.to_s, content_type: upload.content_type, bytes: bytes) ]
      end

      Result.new(batch: batch, entries: entries, archive_error: archive_error)
    end

    private

    attr_reader :tenant, :actor, :upload, :batch_name, :inspector, :structured_adapter, :batch, :archive_error, :processed_documents_by_sha

    def read_upload_bytes
      source_io = upload.respond_to?(:tempfile) ? upload.tempfile : upload
      source_io.binmode if source_io.respond_to?(:binmode)
      source_io.rewind if source_io.respond_to?(:rewind)
      source_io.read.to_s.b
    end

    def zip_archive?(bytes)
      upload.original_filename.to_s.downcase.end_with?(".zip") ||
        upload.content_type.to_s.include?("zip") ||
        bytes.start_with?("PK\x03\x04".b)
    end

    def zip_upload? = @zip_upload

    def process_zip(bytes, original_filename:)
      return reject_archive("ZIP archive exceeds maximum allowed size") if bytes.bytesize > MAX_ARCHIVE_BYTES

      entries = []
      Zip::File.open_buffer(StringIO.new(bytes), create: false) do |zip_file|
        processable_entries = zip_file.reject { |entry| ignored_zip_entry?(entry) }
        return reject_archive("ZIP archive contains too many invoice files") if processable_entries.size > MAX_ZIP_ENTRIES

        total_uncompressed_size = processable_entries.sum { |entry| entry.size.to_i }
        return reject_archive("ZIP archive uncompressed size exceeds maximum allowed size") if total_uncompressed_size > MAX_ZIP_UNCOMPRESSED_BYTES

        entries = processable_entries.map do |entry|
          safe_basename = safe_zip_entry_name(entry.name)
          unless safe_basename
            next EntryResult.new(status: "rejected", sha256: nil, route: "quarantine", document: nil, rejection_code: "MALICIOUS_FILENAME", message: "filename contains unsafe path characters")
          end

          if entry.size.to_i > MAX_ZIP_ENTRY_BYTES
            next EntryResult.new(status: "rejected", sha256: nil, route: "quarantine", document: nil, rejection_code: "FILE_TOO_LARGE", message: "file exceeds maximum allowed size")
          end

          entry_bytes = entry.get_input_stream.read.to_s.b
          process_entry(
            filename: safe_basename,
            content_type: Rack::Mime.mime_type(File.extname(safe_basename), "application/octet-stream"),
            bytes: entry_bytes
          )
        end
      end
      entries
    rescue Zip::Error
      reject_archive("ZIP archive could not be read")
    end

    def reject_archive(message)
      @archive_error = message
      []
    end

    def ignored_zip_entry?(entry)
      entry.directory? || entry.name.start_with?("__MACOSX/") || File.basename(entry.name) == ".DS_Store"
    end

    def safe_zip_entry_name(entry_name)
      name = entry_name.to_s
      return nil if name.blank? || name.include?("\0") || name.include?("\\") || name.start_with?("/")
      return nil if name.split("/").include?("..")

      basename = File.basename(name)
      return nil if basename.blank? || basename == "."

      basename
    end

    def process_entry(filename:, content_type:, bytes:)
      safe_filename = filename.to_s
      inspection = inspector.inspect_bytes(bytes, filename: safe_filename, content_type: content_type)

      return rejected_entry(inspection) if inspection.rejected?

      if (existing_document = processed_documents_by_sha[inspection.sha256])
        return EntryResult.new(status: "duplicate", sha256: inspection.sha256, route: inspection.route, document: existing_document, rejection_code: "DUPLICATE_SOURCE", message: "duplicate source file")
      end

      entry = if inspection.accepted? && inspection.route == "structured_parser"
        process_structured_entry(inspection:, safe_filename:, bytes:)
      elsif inspection.accepted? && %w[visual_model hybrid_compare].include?(inspection.route)
        process_direct_entry(inspection:, safe_filename:, bytes:, target_status: "routed_visual", event_action: "upload_routed")
      elsif inspection.quarantined?
        process_direct_entry(inspection:, safe_filename:, bytes:, target_status: "quarantined", event_action: "upload_quarantined", rejection_code: inspection.rejection_code)
      else
        process_direct_entry(inspection:, safe_filename:, bytes:, target_status: "quarantined", event_action: "upload_quarantined", rejection_code: inspection.rejection_code || "UNSUPPORTED_INTAKE_ROUTE")
      end

      processed_documents_by_sha[inspection.sha256] = entry.document if entry.document.present?
      entry
    end

    def rejected_entry(inspection)
      EntryResult.new(status: "rejected", sha256: inspection.sha256, route: inspection.route, document: nil, rejection_code: inspection.rejection_code, message: inspection.message)
    end

    def process_structured_entry(inspection:, safe_filename:, bytes:)
      structured = structured_adapter.call(xml: bytes, filename: safe_filename)

      if structured.mapped?
        wrapped = StructuredPersistenceResult.new(
          candidate: structured.canonical,
          idempotency_key: "operator-structured-#{inspection.sha256}",
          provenance: {
            route: inspection.route,
            family: inspection.detection&.family,
            profile: inspection.detection&.profile,
            profile_version: inspection.detection&.version,
            provider: "structured_parser",
            provider_version: inspection.detection&.version,
            model: "deterministic_structured_adapter",
            model_version: inspection.detection&.profile
          }.compact,
          error_code: nil
        )

        document = Review::ProviderResultIngester.call(
          batch: batch!,
          source_sha256: inspection.sha256,
          result: wrapped,
          source_metadata: source_metadata_for(inspection),
          actor: actor
        )
        attach_source(document:, safe_filename:, content_type: inspection.sniffed_mime_type, bytes:)
        document.reload
        return EntryResult.new(status: document.status, sha256: inspection.sha256, route: inspection.route, document: document, rejection_code: nil, message: nil)
      end

      rejection_code = structured.errors.first || inspection.rejection_code || "UNSUPPORTED_STRUCTURED_FORMAT"
      process_direct_entry(inspection:, safe_filename:, bytes:, target_status: "quarantined", event_action: "upload_quarantined", rejection_code: rejection_code)
    end

    def process_direct_entry(inspection:, safe_filename:, bytes:, target_status:, event_action:, rejection_code: nil)
      document = batch!.documents.find_or_initialize_by(source_sha256: inspection.sha256)
      document.assign_attributes(
        status: target_status,
        source_filename_digest: Digest::SHA256.hexdigest(safe_filename.to_s),
        source_format_family: inspection.detection&.family,
        source_format_profile: inspection.detection&.profile,
        source_format_version: inspection.detection&.version,
        route: inspection.route,
        source_metadata: source_metadata_for(inspection),
        processing_provenance: { intake: inspection.observability.deep_stringify_keys }
      )
      changed_for_event = document.new_record? || document.changed?
      document.save!
      attach_source(document:, safe_filename:, content_type: inspection.sniffed_mime_type, bytes:)

      if changed_for_event
        document.events.create!(
          batch: document.batch,
          actor: actor,
          action: event_action,
          reason: "operator upload",
          metadata: { route: inspection.route, rejection_code: rejection_code }.compact
        )
      end

      if target_status == "routed_visual"
        Review::ProcessDocumentJob.perform_now(document.id)
        document.reload.batch.refresh_status!
      else
        document.batch.refresh_status!
        document.reload
      end

      EntryResult.new(status: document.status, sha256: inspection.sha256, route: inspection.route, document: document, rejection_code: nil, message: nil)
    end

    def attach_source(document:, safe_filename:, content_type:, bytes:)
      return if document.source_file.attached?

      document.source_file.attach(
        io: StringIO.new(bytes),
        filename: safe_filename,
        content_type: content_type || "application/octet-stream",
        identify: false
      )
    end

    def source_metadata_for(inspection)
      {
        "mime_type" => inspection.sniffed_mime_type,
        "page_count" => inspection.metadata[:page_count] || inspection.metadata["page_count"],
        "byte_size" => inspection.byte_size,
        "route_profile_version" => inspection.detection&.version,
        "rejection_code" => inspection.rejection_code,
        "declared_content_type" => inspection.declared_content_type,
        "content_type_mismatch" => inspection.observability[:content_type_mismatch]
      }.compact
    end

    def batch!
      @batch ||= Review::Batch.create!(
        tenant: tenant,
        name: batch_name.presence || default_batch_name,
        metadata: { upload_source: "operator_ui", upload_kind: zip_upload? ? "zip" : "single_invoice", actor: actor }
      )
    end

    def default_batch_name
      "Operator upload #{Time.current.utc.strftime("%Y-%m-%d %H:%M UTC")}"
    end
  end
end
