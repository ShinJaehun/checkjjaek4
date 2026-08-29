Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "homes#show"
  devise_for :users, controllers: { registrations: "users/registrations", sessions: "users/sessions" }
  resource :account_withdrawal, only: %i[show destroy]
  get "/relationships", to: "relationships#index"
  resources :notifications, only: :index
  namespace :admin do
    resources :users, only: %i[index show] do
      patch :suspend, on: :member
      patch :restore, on: :member
    end
    resources :groups, only: %i[index show] do
      patch :approve, on: :member
    end
  end
  resources :groups, only: %i[index show new create edit update] do
    patch :close, on: :member
    patch :request_reactivation, on: :member
    patch :transfer_admin, on: :member
    resources :group_memberships, only: %i[create update destroy] do
      post :invite, on: :collection
      patch :accept, on: :member
      delete :decline, on: :member
      delete :reject, on: :member
      delete :revoke, on: :member
      delete :remove, on: :member
      patch :deactivate, on: :member
      patch :reactivate, on: :member
    end
    resources :jjaeks, only: :create
  end
  resource :book_search, only: :show, controller: "book_searches"
  resources :books, only: :show do
    collection do
      get :lookup
    end
  end
  resources :bookshelf_entries, only: %i[create edit update destroy] do
    patch :move, on: :member
    patch :bulk_move, on: :collection
    patch :reorder, on: :collection
  end
  resources :bookshelves, only: %i[create update destroy] do
    patch :move_up, on: :member
    patch :move_down, on: :member
  end
  resources :jjaeks, only: %i[new show create edit update destroy] do
    resources :requotes, only: :index
    resources :comments, only: %i[index create update destroy]
    resource :like, only: %i[create destroy]
  end

  resources :users, only: :show do
    resource :library, only: :show, controller: "users/libraries" do
      get :transfer
    end
    resource :follow, only: %i[create destroy]
    resource :book_friendship, only: %i[create update destroy]
  end
end
