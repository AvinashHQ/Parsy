# frozen_string_literal: true

module Review
  class BatchProgress
    def self.call(batch)
      batch.progress
    end
  end
end
