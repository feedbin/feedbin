# config valid only for current version of Capistrano
lock "3.11.0"

set :branch, "master"

set :application, "feedbin"
set :repo_url, "git@github.com:feedbin/#{fetch(:application)}.git"
set :deploy_to, "/srv/apps/#{fetch(:application)}"
set :bundle_jobs, 4
set :rbenv_type, :system
set :log_level, :warn

# Rails
set :assets_roles, [:app]
set :keep_assets, 2
set :conditionally_migrate, true

append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "vendor/bundle", "public/system", "public/uploads"

before "deploy", "deploy:quiet"
after "deploy:published", "deploy:restart"
