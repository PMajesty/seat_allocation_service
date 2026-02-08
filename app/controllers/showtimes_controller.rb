class ShowtimesController < ApplicationController
  before_action :authenticate_user!

  def show
    @showtime = Showtime.includes(:event, :venue).find(params[:id])
    @event = @showtime.event
    @venue = @showtime.venue
  end
end
