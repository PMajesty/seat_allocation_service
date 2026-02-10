class Event < ApplicationRecord
  include EventSearchable

  has_many :showtimes
  has_many :scheduled_showtimes, -> { scheduled.order(:starts_at) }, class_name: "Showtime"

  scope :ordered_by_closest_showtime, -> {
    left_joins(:scheduled_showtimes)
      .group(:id)
      .order(Arel.sql("MIN(CASE WHEN showtimes.starts_at >= ? THEN showtimes.starts_at END) ASC NULLS LAST", Time.current))
  }

  def thumbnail_color
    digest = Digest::MD5.hexdigest(title)
    "##{digest[0..5]}"
  end
end
