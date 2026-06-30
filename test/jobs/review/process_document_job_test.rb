# frozen_string_literal: true

require "test_helper"

module Review
  class ProcessDocumentJobTest < ActiveSupport::TestCase
    setup do
      @tenant = Tenant.create!(name: "Job Tenant", slug: "job-#{SecureRandom.hex(4)}")
      @batch = @tenant.review_batches.create!(name: "Job Batch")
    end

    test "runs extraction for a document without a candidate revision" do
      document = @batch.documents.create!(source_sha256: "job-sha-1", status: "needs_review", route: "visual_model")
      extracted = []

      with_extractor_stub(->(document:) { extracted << document.id; document }) do
        Review::ProcessDocumentJob.perform_now(document.id)
      end

      assert_equal [ document.id ], extracted
    end

    test "does nothing for an already-exported document" do
      document = @batch.documents.create!(source_sha256: "job-sha-2", status: "exported")

      with_extractor_stub(->(**) { flunk "must not extract terminal documents" }) do
        Review::ProcessDocumentJob.perform_now(document.id)
      end

      assert_equal "exported", document.reload.status
    end

    private

    def with_extractor_stub(callable)
      original = Extraction::DocumentExtractor.method(:call)
      Extraction::DocumentExtractor.singleton_class.define_method(:call) { |**kwargs| callable.call(**kwargs) }
      yield
    ensure
      Extraction::DocumentExtractor.singleton_class.define_method(:call, original)
    end
  end
end
