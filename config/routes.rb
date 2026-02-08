Rails.application.routes.draw do
  root to: "home#index"

  get "/signup", to: "registrations#new"
  post "/signup", to: "registrations#create"

  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  get "/dashboard", to: "dashboard#index"
  post "/dashboard/simulation", to: "dashboard#update_simulation"

  resources :showtimes, only: [:show]

  namespace :api do
    namespace :v1 do
      resources :showtimes, only: [] do
        member do
          get :seats
          post :holds, to: "holds#create"
          delete :holds, to: "holds#destroy"
          post :checkout, to: "checkouts#create"
        end
      end
    end
  end
end
