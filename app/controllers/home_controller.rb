class HomeController < ApplicationController
  def index
    if params[:q].to_s.present?
      begin
        page = (params[:page] || 1).to_i
        per_page = Kaminari.config.default_per_page

        response = Event.search_events(params[:q], page: page, per_page: per_page)

        @events = Kaminari.paginate_array(
          response.records.preload(:scheduled_showtimes).to_a,
          total_count: response.results.total
        ).page(page).per(per_page)

      rescue Elastic::Transport::Transport::Error, Faraday::ConnectionFailed => e
        Rails.error.report(e, handled: true, severity: :warning)

        flash.now[:alert] = "Search is currently under maintenance. Please try again later."
        @events = Event.none
      end
    else
      @events = Event.ordered_by_closest_showtime.page(params[:page]).preload(:scheduled_showtimes)
    end
  end
end
