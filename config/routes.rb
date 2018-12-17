require "sidekiq/web"

Sidekiq::Web.set :session_secret, Rails.application.secrets.secret_key_base
Sidekiq::Web.app_url = ENV["FEEDBIN_URL"]

Rails.application.routes.draw do

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  root to: "site#index"

  mount StripeEvent::Engine, at: "/stripe"
  constraints lambda { |request| AuthConstraint.admin?(request) } do
    mount Sidekiq::Web => "sidekiq"
  end
  get :health_check, to: proc { |env| [200, {}, ["OK"]] }
  get :version, to: proc { |env| [200, {}, [File.read("REVISION")]] }
  get :subscribe, to: "site#subscribe"

  post "/emails" => "emails#create"
  post "/newsletters" => "newsletters#create"

  match "/404", to: "errors#not_found", via: :all
  get "/starred/:starred_token", to: "starred_entries#index", as: "starred"
  post "/starred/export", to: "starred_entries#export"

  get :signup, to: "users#new", as: "signup"
  get :login, to: "sessions#new", as: "login"
  delete :logout, to: "sessions#destroy", as: "logout"

  get ".well-known/apple-app-site-association", to: "well_known#apple_site_association"
  get ".well-known/apple-developer-merchantid-domain-association", to: "well_known#apple_pay"
  get ".well-known/change-password", to: "well_known#change_password"


  # Apple Push

  # When a user allows permission to receive push notifications
  post "apple_push_notifications/:version/pushPackages/:website_push_id", as: :apple_push_notifications_package, to: "apple_push_notifications#create", website_push_id: /.*/

  # POST When users first grant permission, or later change their permission
  # levels for your website
  post "apple_push_notifications/:version/devices/:device_token/registrations/:website_push_id", as: :apple_push_notifications_update, to: "apple_push_notifications#update", website_push_id: /.*/

  # DELETE If a user removes permission of a website in Safari preferences, a
  # DELETE request is sent
  delete "apple_push_notifications/:version/devices/:device_token/registrations/:website_push_id", as: :apple_push_notifications_delete, to: "apple_push_notifications#delete", website_push_id: /.*/

  # Error log
  post "apple_push_notifications/:version/log", as: :apple_push_notifications_log, to: "apple_push_notifications#log"

  resource :app, only: [] do
    member do
      get :login
      get :redirect
    end
  end

  resources :tags, only: [:index, :show, :update, :destroy]
  resources :billing_events, only: [:show]
  resources :in_app_purchases, only: [:show]
  resources :password_resets
  resources :sharing_services, path: "settings/sharing", only: [:index, :create, :update, :destroy]
  resources :actions, path: "settings/actions", only: [:index, :create, :new, :update, :destroy, :edit]
  resources :saved_searches, only: [:show, :update, :destroy, :create] do
    collection do
      get :count
    end
  end

  resources :public_settings, only: [] do
    member do
      get :email_unsubscribe
    end
    collection do
      get :account_closed
    end
  end

  resources :sessions do
    collection do
      get :refresh
    end
  end

  resources :supported_sharing_services, only: [:create, :destroy, :update] do
    member do
      get :oauth_response
      get :autocomplete
      match "share/:entry_id", to: "supported_sharing_services#share", as: :share, via: [:get, :post]
    end
  end

  resources :subscriptions, only: [:index, :create, :destroy, :update] do
    member do
      delete :feed_destroy
    end
  end

  resources :embeds, only: [] do
    collection do
      get :twitter
      get :instagram
      get :iframe
    end
  end

  resources :users, id: /.*/ do
    member do
      patch :settings_update, controller: :settings
      patch :view_settings_update, controller: :settings
    end
  end

  resources :feeds, only: [:index, :edit, :create, :update] do
    patch :rename
    resources :entries, only: [:index], controller: :feeds_entries
    collection do
      get :view_unread
      get :view_all
      get :view_starred
      get :auto_update
      get :update_styles
      post :search
    end
    member do
      match :push, via: [:post, :get]
      post :toggle_updates
      get :modal_edit
      get :edit_tags
    end
  end

  resources :entries, only: [:show, :index] do
    member do
      post :content
      post :unread_entries, to: "unread_entries#update"
      post :starred_entries, to: "starred_entries#update"
      post :mark_as_read, to: "entries#mark_as_read"
      post :recently_read, to: "recently_read_entries#create"
      post :recently_played, to: "recently_played_entries#create"
      get :push_view
      get :diff
      get :newsletter
    end
    collection do
      get :starred
      get :unread
      get :preload
      get :search
      get :recently_read, to: "recently_read_entries#index"
      get :recently_played, to: "recently_played_entries#index"
      get :updated, to: "updated_entries#index"
      post :view_link
      post :view_link_contents
      post :view_link_cache
      post :mark_all_as_read
      post :mark_direction_as_read
    end
  end

  get :settings, to: "settings#settings"
  namespace :settings do
    resources :subscriptions do
      collection do
        patch :update_multiple
      end
      member do
        post :refresh_favicon
      end
    end
    get :account
    get :billing
    get :import_export
    get :appearance
    post :update_credit_card
    post :update_plan
    post :font
    post :theme
    post :font_increase
    post :font_decrease
    post :entry_width
    post :now_playing
    post :audio_panel_size
  end

  post "settings/sticky/:feed_id", as: :settings_sticky, to: "settings#sticky"

  resources :twitter_authentications, only: [:new] do
    collection do
      get :save
      delete :delete
    end
  end

  resources :tweets, only: [] do
    member do
      get :thread
    end
  end

  resources :microposts, only: [] do
    member do
      get :thread
    end
  end

  resources :recently_read_entries, only: [] do
    collection do
      delete :destroy_all
    end
  end

  resources :recently_played_entries, only: [] do
    collection do
      delete :destroy_all
    end
  end

  constraints subdomain: "api" do
    namespace :api, path: nil do
      namespace :v1 do
        match "*path", to: "api#gone", via: :all
      end
    end
  end

  constraints subdomain: "api" do
    namespace :api, path: nil do
      namespace :v2 do
        resources :feeds, only: [:show] do
          resources :entries, only: [:index, :show], controller: :feeds_entries
        end

        resources :entry_counts, only: [] do
          collection do
            get :post_frequency
          end
        end

        resources :actions, only: [:index, :create, :update] do
          member do
            get :results
          end
          collection do
            get :results_watch
          end
        end

        resources :devices, only: [:create] do
          collection do
            get :ios_test
            get :safari_test
          end
        end

        resources :users, only: [:create] do
          collection do
            get :info
          end
        end

        resources :tags, only: [:index] do
          collection do
            post :update
            delete :destroy
          end
        end

        resources :subscriptions, only: [:index, :show, :create, :destroy, :update]
        resources :favicons, only: [:index]
        resources :taggings, only: [:index, :show, :create, :destroy]
        resources :recently_read_entries, only: [:index, :create]
        resources :in_app_purchases, only: [:create]
        resources :suggested_categories, only: [:index]

        resources :entries, only: [:index, :show] do
          member do
            get :text
            get :watch
          end
        end
        resources :suggested_feeds, only: [:index] do
          member do
            post :subscribe
            delete :unsubscribe
          end
        end

        get :authentication, to: "authentication#index"

        post "subscriptions/:id/update", to: "subscriptions#update"

        resources :unread_entries, only: [:index, :show, :create]
        delete "unread_entries", to: "unread_entries#destroy"
        put "unread_entries", to: "unread_entries#create"
        post "unread_entries/delete", to: "unread_entries#destroy"

        resources :starred_entries, only: [:index, :show, :create]
        delete "starred_entries", to: "starred_entries#destroy"
        put "starred_entries", to: "starred_entries#create"
        post "starred_entries/delete", to: "starred_entries#destroy"

        resources :updated_entries, only: [:index]
        delete "updated_entries", to: "updated_entries#destroy"
        post "updated_entries/delete", to: "updated_entries#destroy"

        resources :saved_searches, only: [:index, :show, :create, :destroy, :update]
        post "saved_searches/:id/update", to: "saved_searches#update"
      end
    end
  end

  namespace :admin do
    resources :users
  end
end
