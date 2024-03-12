require "sidekiq/web"
Sidekiq::Web.app_url = ENV["FEEDBIN_URL"]

Rails.application.routes.draw do
  root to: "site#index"

  mount StripeEvent::Engine, at: "/stripe"

  constraints lambda { |request| AuthConstraint.admin?(request) } do
    mount Lookbook::Engine, at: "/lookbook"
  end

  constraints lambda { |request| AuthConstraint.admin?(request) } do
    mount Sidekiq::Web, at: "/sidekiq"
  end

  get :health_check, to: proc { |env| [200, {}, ["OK"]] }
  get :version, to: proc { |env| [200, {}, [File.read("REVISION")]] }
  get :subscribe, to: "site#subscribe"
  get :service_worker, to: "site#service_worker"
  get "manifest/:theme", to: "site#manifest", as: "manifest"

  get "bookmarklet/:cache_buster", to: "bookmarklet#script", as: "bookmarklet"

  match "/404", to: "errors#not_found", via: :all
  get "/starred/:starred_token", to: "starred_entries#index", as: "starred"
  post "/starred/export", to: "starred_entries#export"

  get :signup, to: "users#new", as: "signup"
  get :login, to: "sessions#new", as: "login"
  delete :logout, to: "sessions#destroy", as: "logout"

  get ".well-known/apple-app-site-association", to: "well_known#apple_site_association"
  get ".well-known/apple-developer-merchantid-domain-association", to: "well_known#apple_pay"
  get ".well-known/change-password", to: "well_known#change_password"

  # WebSub
  get  "web_sub/:id/:signature", as: :web_sub_verify,  to: "web_sub#verify"
  post "web_sub/:id/:signature", as: :web_sub_publish, to: "web_sub#publish"

  resource :app, only: [] do
    member do
      get :login
      get :redirect
    end
  end

  resources :newsletters, only: :create
  resources :tags, only: [:index, :show, :update, :destroy, :edit]
  resources :billing_events, only: [:show]
  resources :in_app_purchases, only: [:show]
  resources :app_store_notifications, only: [:show]
  resources :password_resets
  resources :sharing_services, path: "settings/sharing", only: [:index, :create, :update, :destroy]
  resources :actions, path: "settings/actions", only: [:index, :create, :new, :update, :destroy, :edit]
  resources :devices, only: [:create]
  resources :account_migrations, path: "settings/account_migrations" do
    member do
      patch :start
    end
  end
  resources :fix_feeds, path: "settings/subscriptions/fix" do
    collection do
      post :replace_all
    end
  end
  resources :saved_searches, only: [:show, :update, :destroy, :create, :edit, :new] do
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
      get :oauth2_response
      get :autocomplete
      match "share/:entry_id", to: "supported_sharing_services#share", as: :share, via: [:get, :post]
    end
  end

  resources :subscriptions, only: [:index, :edit, :create, :destroy, :update]

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
      patch :format, controller: :settings
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
      post :search
    end
    member do
      get :modal_edit
      get :edit_tags
      get :pages, to: "pages_entries#index"
    end
  end

  resources :entries, only: [:show, :index, :destroy] do
    member do
      post :content
      post :unread_entries, to: "unread_entries#update"
      post :starred_entries, to: "starred_entries#update"
      post :mark_as_read, to: "entries#mark_as_read"
      post :recently_read, to: "recently_read_entries#create"
      post :recently_played, to: "recently_played_entries#create"
      get :push_view
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
      post :mark_all_as_read
      post :mark_direction_as_read
    end
  end

  get :settings, to: "settings#index"
  namespace :settings do
    resources :subscriptions, only: [:index, :edit, :destroy, :update] do
      collection do
        patch :update_multiple
      end
      member do
        post :refresh_favicon
        patch :newsletter_senders
      end
    end

    resources :imports, only: [:create, :show] do
      member do
        post :replace_all
      end
    end

    resources :import_items, only: [:update]
    get :import_export, to: "imports#index"

    get :billing, to: "billings#index"
    resource :billing, only: [] do
      collection do
        get :edit
        get :payment_history
        get :payment_details
        post :update_credit_card
        post :update_plan
      end
    end

    get :account
    get :appearance
    get :newsletters_pages
    post :now_playing
    post :audio_panel_size
  end

  post "settings/sticky/:feed_id", as: :settings_sticky, to: "settings#sticky"
  post "settings/subscription_view_mode/:feed_id", as: :settings_subscription_view_mode, to: "settings#subscription_view_mode"

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

  resources :queued_entries, only: [:index]

  resources :recently_played_entries, only: [] do
    collection do
      delete :destroy_all
      get :progress
    end
  end

  resources :extracts, only: [] do
    member do
      get :entry
    end
    collection do
      get :modal
      get :cache
    end
  end

  resources :remote_files, path: :files, only: [] do
    collection do
      get "icons/:signature/:url", action: :icon, as: :icon
    end
  end

  match "pages",          to: "pages#create",          via: :post
  match "pages",          to: "pages#options",         via: :options
  match "pages",          to: "pages#fallback",        via: :get
  match "pages_internal", to: "pages_internal#create", via: :post

  constraints subdomain: "api" do
    namespace :api, path: nil do
      namespace :v1 do
        match "*path", to: "api#gone", via: :all
      end
    end
  end

  constraints subdomain: "api" do
    namespace :api, path: nil do
      namespace :public do
        namespace :v1 do
          resources :feeds, only: :show
        end
      end

      namespace :podcasts do
        namespace :v1 do
          resources :feeds, only: :show
          resources :subscriptions, only: [:index, :create, :update, :destroy]
          namespace :queued_entries do
            resource :bulk, controller: :bulk, only: [:update]
          end
          resources :queued_entries, only: [:index, :create, :update, :destroy]
          resources :playlists, only: [:index, :create, :update, :destroy]
          post :authentication, to: "authentication#index"
        end
      end

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
            patch :update
            delete :destroy
          end
        end

        resources :tags, only: [:index] do
          collection do
            post :update
            delete :destroy
          end
        end

        resources :imports, only: [:index, :create, :show]
        resources :subscriptions, only: [:index, :show, :create, :destroy, :update]

        resources :favicons, only: [:index]
        resources :icons, only: [:index]
        resources :taggings, only: [:index, :show, :create, :destroy]
        resources :recently_read_entries, only: [:index, :create]
        resources :in_app_purchases, only: [:create]
        resources :suggested_categories, only: [:index]
        resources :authentication_tokens, only: [:create]

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

        resources :pages, only: [:create]

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

  constraints lambda { |request| AuthConstraint.admin?(request) } do
    namespace :admin do
      resources :users
      resources :feeds
    end
  end

  namespace :app_store do
    resources :notifications_v2, only: :create
  end

end
