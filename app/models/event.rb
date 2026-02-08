class Event < ApplicationRecord
  has_many :showtimes
  has_many :scheduled_showtimes, -> { scheduled.order(:starts_at) }, class_name: "Showtime"

  def thumbnail_color
    digest = Digest::MD5.hexdigest(title)
    "##{digest[0..5]}"
  end
end
