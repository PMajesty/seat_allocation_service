class User < ApplicationRecord
  has_secure_password

  enum :role, { visitor: 0, admin: 1 }

  has_many :orders
end
