class Venue < ApplicationRecord
  has_many :seats
  has_many :showtimes
end
