Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "homes#show"
  devise_for :users
  get "/relationships", to: "relationships#index"
  resources :notifications, only: :index
  resource :book_search, only: :show, controller: "book_searches"
  resources :books, only: :show do
    collection do
      get :lookup
    end
  end
  resources :bookshelf_entries, only: %i[create edit update destroy] do
    patch :move, on: :member
  end
  resources :bookshelves, only: %i[create update destroy] do
    patch :move_up, on: :member
    patch :move_down, on: :member
  end
  resources :jjaeks, only: %i[new show create edit update destroy] do
    resources :comments, only: %i[create update destroy]
    resource :like, only: %i[create destroy]
  end

  resources :users, only: :show do
    resource :library, only: :show, controller: "users/libraries"
    resource :follow, only: %i[create destroy]
    resource :book_friendship, only: %i[create update destroy]
  end
end
