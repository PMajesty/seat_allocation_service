class HomeController < ApplicationController
  def index
    @events = Event.where(active: true).includes(:scheduled_showtimes)
  end
end
