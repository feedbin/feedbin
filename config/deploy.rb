require "bundler/capistrano"
require 'capistrano-unicorn'

set :user,        'app'
set :application, "feedbin"
set :use_sudo,    false

set :scm,           :git
set :repository,    "git@github.com:feedbin/feedbin.git"
set :branch,        'master'
set :keep_releases, 5
set :deploy_via,    :remote_cache

set :ssh_options, { forward_agent: true }
set :deploy_to,   "/srv/apps/#{application}"

# TODO see if this can be removed if `sudo bundle` stops failing
set :bundle_cmd, "/usr/local/rbenv/shims/bundle"

# Gets rid of trying to link public/* directories
set :normalize_asset_timestamps, false

set :unicorn_pid, "#{shared_path}/pids/unicorn.pid"
set :unicorn_bundle, bundle_cmd

set :assets_role, [:app]

role :app, "www1.feedbin.me", "www2.feedbin.me", "www3.feedbin.me"
role :worker, "worker1.feedbin.me", "worker2.feedbin.me"

default_run_options[:pty] = true
default_run_options[:shell] = '/bin/bash --login'

namespace :foreman do

  task :export_worker, roles: :worker do
    foreman_export = "foreman export --app #{application} --user #{user} --concurrency worker=3,worker_slow=2,clock=1 --log #{shared_path}/log upstart /etc/init"
    run "cd #{current_path} && sudo #{bundle_cmd} exec #{foreman_export}"
  end

  desc 'Start the application services'
  task :start do
    run "sudo start #{application}"
  end

  desc 'Stop the application services'
  task :stop do
    run "sudo stop #{application}"
  end

  desc 'Restart worker services'
  task :restart_worker, roles: :worker  do
    run "sudo start #{application} || sudo restart #{application} || true"
  end

  desc "Zero-downtime restart of Unicorn"
  task :restart_web, roles: :web  do
    unicorn.restart
  end

end

namespace :deploy do
  desc 'Start the application services'
  task :start do
    foreman.start
  end

  desc 'Stop the application services'
  task :stop do
    foreman.stop
  end
end

after 'deploy:update', 'foreman:export_worker'
after "deploy:restart", "foreman:restart_worker"
after "deploy:restart", "foreman:restart_web"
after "deploy:restart", "deploy:cleanup"
