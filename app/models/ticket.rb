class Ticket < ApplicationRecord
  belongs_to :order
  belongs_to :showtime_seat

  enum :status, { valid: 0, void: 1 }, prefix: true
end
