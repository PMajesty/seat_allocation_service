class Ticket < ApplicationRecord
  belongs_to :order
  belongs_to :showtime_seat

  enum :status, { valid: 0, void: 1 }, prefix: true

  before_validation :generate_code, on: :create

  private

  def generate_code
    self.code ||= loop do
      random_code = SecureRandom.hex(4).upcase
      break random_code unless Ticket.exists?(code: random_code)
    end
  end
end
