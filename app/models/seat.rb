class Seat < ApplicationRecord
  belongs_to :venue
  has_many :showtime_seats
end
