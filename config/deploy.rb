# config valid only for current version of Capistrano
lock "3.9.1"

ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

set :application, "feedbin"
set :repo_url, "git@github.com:feedbin/#{fetch(:application)}.git"
set :deploy_to, "/srv/apps/#{fetch(:application)}"
set :bundle_jobs, 4
set :rbenv_type, :system
set :log_level, :info
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto
set :pty, true

# Rails
set :assets_roles, [:app]
set :keep_assets, 2
set :migration_servers, -> { primary(fetch(:migration_role)) }
set :migration_role, :app
set :conditionally_migrate, true

append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "vendor/bundle", "public/system", "public/uploads"

before "deploy", "deploy:quiet"
after "deploy:published", "deploy:restart"
