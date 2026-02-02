class HomeController < ApplicationController
  def index
    render json: {
      service: "Seat Allocation Service",
      version: "1.0",
      status: "healthy",
      sample_data: {
        venues: Venue.count,
        events: Event.count,
        showtimes: Showtime.count
      }
    }
  end
end
