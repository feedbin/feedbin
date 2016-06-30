require 'bundler/capistrano'

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

set :assets_role, [:app]

role :app, "app1.feedbin.com", "app2.feedbin.com", "app3.feedbin.com"

default_run_options[:pty] = true
default_run_options[:shell] = '/bin/bash --login'

namespace :deploy do
  desc 'Start the application services'
  task :start do
    run "sudo /etc/init.d/unicorn start"
    run "sudo start clock"
    run "sudo start workers"
    run "sudo start workers_slow"
  end

  desc 'Stop the application services'
  task :stop do
    run "sudo /etc/init.d/unicorn stop"
    run "sudo stop clock"
    run "sudo stop workers"
    run "sudo stop workers_slow"
  end

  desc 'Restart services'
  task :restart do
    run "sudo /etc/init.d/unicorn start || sudo /etc/init.d/unicorn reload"
    run "sudo start clock || sudo restart clock || true"
    run "sudo start workers || sudo restart workers"
    run "sudo start workers_slow || sudo restart workers_slow"
  end

  desc 'Quiet Sidekiq'
  task :quiet do
    run "sudo pkill --signal USR1 -f '^sidekiq'; true"
  end

  desc 'Reload procs'
  task :reload do
    quiet
    sleep(3)
    restart
  end

end

before 'deploy:update', 'deploy:quiet'
