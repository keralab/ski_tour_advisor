Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "analyses#new"
  resources :analyses, only: [:new, :create, :show] do
    collection do
      post :latest
      post :historical
    end
  end
end
