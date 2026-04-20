Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "homes#show"
  devise_for :users
  resource :book_search, only: :show, controller: "book_searches"
  resources :books, only: :show do
    collection do
      get :lookup
    end
  end
  resources :bookshelf_entries, only: %i[index new create edit update destroy]
  resources :jjaeks, only: %i[new show create edit update destroy] do
    resources :comments, only: %i[create update destroy]
    resource :like, only: %i[create destroy]
  end

  resources :users, only: :show do
    resource :follow, only: %i[create destroy]
    resource :book_friendship, only: %i[create update destroy]
  end
end
