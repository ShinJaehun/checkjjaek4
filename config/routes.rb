Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "posts#index"
  devise_for :users

  resources :posts, except: %i[new] do
    resources :comments, only: %i[create update destroy]
    resource :like, only: %i[create destroy]
  end

  resources :users, only: :show do
    resource :follow, only: %i[create destroy]
  end
end
