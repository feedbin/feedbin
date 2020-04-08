# config valid only for current version of Capistrano
lock "3.12.1"

set :branch, "master"

set :application, "feedbin"
set :repo_url, "git@github.com:feedbin/#{fetch(:application)}.git"
set :deploy_to, "/srv/apps/#{fetch(:application)}"
set :bundle_jobs, 6
set :log_level, :warn

# Rails
set :assets_roles, [:app]
set :keep_assets, 10
set :conditionally_migrate, true

append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "vendor/bundle", "public/system", "public/uploads"
append :linked_files, ".env", "config/librato.yml"

before "deploy", "deploy:quiet"
after "deploy:published", "deploy:restart"
