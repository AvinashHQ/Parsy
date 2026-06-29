# frozen_string_literal: true

module Review
  class ExportArtifact < ApplicationRecord
    self.table_name = "export_artifacts"

    FORMATS = %w[json csv xlsx].freeze

    belongs_to :batch, class_name: "Review::Batch", foreign_key: :review_batch_id, inverse_of: :export_artifacts

    has_one_attached :file

    validates :format, inclusion: { in: FORMATS }
    validates :status, presence: true
  end
end
