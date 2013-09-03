require 'sidekiq/web'

Feedbin::Application.routes.draw do

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  root to: 'site#index'
  
  mount Sidekiq::Web, at: '/sidekiq'
  mount StripeEvent::Engine, at: '/stripe'
  
  get :health_check, to: proc {|env| [200, {}, ["OK"]] }

  get :home, to: 'site#home'
  
  post '/emails' => 'emails#create'
  
  match '/404', to: 'errors#not_found', via: :all
  get '/starred/:starred_token', to: 'starred#index', as: 'starred'
  
  get    :signup,         to: 'users#new',           as: 'signup'
  get    :login,          to: 'sessions#new',        as: 'login'
  get    :privacy_policy, to: 'site#privacy_policy', as: 'privacy_policy'
  delete :logout,         to: 'sessions#destroy',    as: 'logout'
  
  resources :tags,           only: [:index, :show, :update, :destroy]
  resources :billing_events, only: [:show]
  resources :imports
  resources :sessions
  resources :password_resets
  resources :sharing_services, path: 'settings/sharing', only: [:index]

  resources :subscriptions,  only: [:index, :create, :destroy] do
    collection do
      patch :update_multiple
    end
  end

  resources :users, id: /.*/ do
    member do
      patch :settings_update, controller: :settings
      patch :view_settings_update, controller: :settings
      patch :sharing_services_update, controller: :sharing_services
    end
  end
  
  resources :feeds, only: [:index, :edit, :create, :update] do
    resources :entries, only: [:index], controller: :feeds_entries
    collection do
      get :view_unread
      get :view_all
      get :auto_update
    end
  end

  resources :entries, only: [:show, :index] do
    member do
      post :content
      post :unread_entries, to: 'unread_entries#update'
      post :starred_entries, to: 'starred_entries#update'
      post :mark_as_read, to: 'entries#mark_as_read'
    end
    collection do
      get :starred
      get :unread
      get :preload
      post :mark_all_as_read
    end
  end
  
  get :settings, to: 'settings#settings'
  namespace :settings do
    get :account
    get :billing
    get :import_export
    get :feeds
    get :help
    post :update_credit_card
    post :mark_favicon_complete
    post :update_plan
    post :font_increase
    post :font_decrease
    post :entry_width
  end  
  
  constraints subdomain: 'api' do
    namespace :api, path: nil do
      namespace :v1 do
        match '*path', to: 'api#gone', via: :all
      end
    end
  end
  
  constraints subdomain: 'api' do
    namespace :api, path: nil do
      namespace :v2 do
        resources :feeds, only: [:show] do
          resources :entries, only: [:index, :show], controller: :feeds_entries
        end
        resources :subscriptions,  only: [:index, :show, :create, :destroy, :update]
        post "subscriptions/:id/update", to: 'subscriptions#update'
        
        resources :taggings,       only: [:index, :show, :create, :destroy]
        resources :entries,        only: [:index, :show]

        resources :unread_entries, only: [:index, :show, :create]
        delete 'unread_entries', to: 'unread_entries#destroy'
        post 'unread_entries/delete', to: 'unread_entries#destroy'

        resources :starred_entries, only: [:index, :show, :create]
        delete 'starred_entries', to: 'starred_entries#destroy'
        post 'starred_entries/delete', to: 'starred_entries#destroy'
      end
    end
  end
  
end
