class Order < ApplicationRecord
  belongs_to :user
  belongs_to :showtime
  has_many :payments
  has_many :tickets

  enum :status, {
    draft: 0,
    awaiting_payment: 1,
    paid: 2,
    refunded: 3,
    expired: 4,
    canceled: 5
  }
end
