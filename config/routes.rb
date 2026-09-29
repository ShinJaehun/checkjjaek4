Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "homes#show"
  devise_for :users, controllers: { registrations: "users/registrations", sessions: "users/sessions" }
  resource :account_withdrawal, only: %i[show destroy]
  namespace :account do
    resource :settings, only: %i[show update]
  end
  get "/account/relationships", to: "relationships#index", as: :account_relationships
  resources :notifications, only: :index
  namespace :admin do
    resources :jjaeks, only: [] do
      resources :hides, only: %i[new create], controller: "jjaek_hides"
      resources :restorations, only: %i[new create], controller: "jjaek_restorations"
      resources :comments, only: [] do
        resources :hides, only: %i[new create], controller: "comment_hides"
        resources :restorations, only: %i[new create], controller: "comment_restorations"
      end
    end
    resources :users, only: %i[index show] do
      get :content, on: :member
      resources :account_suspensions, only: %i[new create], controller: "user_account_suspensions"
      resources :account_restorations, only: %i[new create], controller: "user_account_restorations"
    end
    resources :groups, only: %i[index show] do
      get :content, on: :member
      patch :approve, on: :member
      resources :operation_suspensions, only: %i[new create], controller: "group_operation_suspensions"
      resources :operation_restorations, only: %i[new create], controller: "group_operation_restorations"
    end
  end
  resources :groups, only: %i[index show new create edit update] do
    resources :members, only: :index, controller: "group_members"
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
      resources :activity_suspensions, only: %i[new create], module: :group_memberships
      resources :activity_restorations, only: %i[new create], module: :group_memberships
      resources :member_bans, only: %i[new create], module: :group_memberships
    end
    resources :group_member_bans, only: [] do
      resources :restorations, only: %i[new create], module: :group_member_bans
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
    resources :group_hides, only: %i[new create], module: :jjaeks
    resources :group_restorations, only: %i[new create], module: :jjaeks
    resources :requotes, only: :index
    resources :comments, only: %i[index create update destroy] do
      resources :group_hides, only: %i[new create], module: :comments
      resources :group_restorations, only: %i[new create], module: :comments
    end
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
