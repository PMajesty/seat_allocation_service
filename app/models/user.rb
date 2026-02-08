class User < ApplicationRecord
  has_secure_password

  enum :role, { visitor: 0, admin: 1 }

  has_many :orders

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  after_commit :clear_cache, on: [:update, :destroy]

  def invalidate_tokens!
    increment!(:token_version)
  end

  def password=(new_password)
    super
    self.token_version = (token_version || 0) + 1
  end

  private

  def clear_cache
    Rails.cache.delete("users/#{id}")
  end
end
