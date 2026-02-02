class ShowtimeSeat < ApplicationRecord
  belongs_to :showtime
  belongs_to :seat
  belongs_to :order, optional: true
  has_one :ticket

  enum :status, { available: 0, reserved: 1, sold: 2 }
end
