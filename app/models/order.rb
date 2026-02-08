class Order < ApplicationRecord
  belongs_to :user
  belongs_to :showtime
  has_many :payments
  has_many :tickets

  enum :status, {
    draft: 0,
    paid: 1
  }
end
