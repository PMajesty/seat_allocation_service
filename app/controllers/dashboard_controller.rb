class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    if (Rails.env.development? || Rails.env.test?) && current_user.admin?
      @simulation_mode = LoadSimulationService.current_mode
    end

    @orders = current_user.orders
                          .includes(tickets: { showtime_seat: :seat }, showtime: [:event, :venue])
                          .where(status: :paid)
                          .order(created_at: :desc)
  end

  def update_simulation
    unless (Rails.env.development? || Rails.env.test?) && current_user.admin?
      head :forbidden
      return
    end

    LoadSimulationService.set_mode(params[:mode])
    redirect_to dashboard_path, notice: "Simulation mode set to #{params[:mode]}"
  end
end
