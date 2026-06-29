# frozen_string_literal: true

class User < ApplicationRecord
  belongs_to :tenant

  attr_reader :operator_token

  validates :email, :name, :role, :operator_token_digest, presence: true
  validates :email, uniqueness: { scope: :tenant_id }

  def operator_token=(token)
    @operator_token = token.to_s
    self.operator_token_digest = self.class.digest_token(@operator_token)
  end

  def authenticate_operator_token(token)
    candidate = self.class.digest_token(token.to_s)
    ActiveSupport::SecurityUtils.secure_compare(operator_token_digest, candidate)
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest("parsy-operator-token-v1:#{token}")
  end
end
