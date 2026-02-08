class Showtime < ApplicationRecord
  belongs_to :event
  belongs_to :venue
  has_many :showtime_seats
  has_many :orders

  enum :status, { scheduled: 0, canceled: 1 }
end
