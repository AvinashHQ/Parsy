# frozen_string_literal: true

class Tenant < ApplicationRecord
  CIRCUIT_BREAKER_STATUSES = %w[closed open].freeze

  has_many :users, dependent: :destroy
  has_many :review_batches, class_name: "Review::Batch", dependent: :restrict_with_exception
  has_many :usage_spend_events, class_name: "Usage::SpendEvent", dependent: :destroy

  validates :name, :slug, :hosting_region, :storage_region, presence: true
  validates :slug, uniqueness: true
  validates :circuit_breaker_status, inclusion: { in: CIRCUIT_BREAKER_STATUSES }
  validates :monthly_spend_limit_cents, :current_spend_cents, numericality: { greater_than_or_equal_to: 0 }

  def processing_provider_allowed?(provider, region: nil)
    allowed_providers.blank? || allowed_providers.include?(provider.to_s)
  end

  def processing_region_allowed?(region)
    region.blank? || allowed_processing_regions.blank? || allowed_processing_regions.include?(region.to_s)
  end

  def privacy_launch_approved?
    privacy_approved_at.present? && privacy_approval.fetch("deletion_verified", false) && privacy_approval.fetch("logging_verified", false)
  end
end
