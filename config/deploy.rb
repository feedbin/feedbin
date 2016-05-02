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

set :assets_role, [:app, :worker]

role :app, "www1.feedbin.com", "www2.feedbin.com", "worker1.feedbin.com", "worker2.feedbin.com"
role :worker, "worker1.feedbin.com", "worker2.feedbin.com"

default_run_options[:pty] = true
default_run_options[:shell] = '/bin/bash --login'

namespace :foreman do

  task :export_procs, roles: :app do
    foreman_export = "foreman export --app #{application} --user #{user} --concurrency clock=1,sidekiq_web=1 --log #{shared_path}/log upstart /etc/init"
    run "cd #{current_path} && sudo #{bundle_cmd} exec #{foreman_export}"
  end

end

namespace :deploy do
  desc 'Start the application services'
  task :start, roles: [:app, :worker] do
    run "sudo /etc/init.d/unicorn start", roles: :app
    run "sudo start #{application}"
    run "sudo start workers", roles: :worker
    run "sudo start workers_slow", roles: :worker
    run "sudo start workers_images", roles: :worker
  end

  desc 'Stop the application services'
  task :stop, roles: [:app, :worker] do
    run "sudo /etc/init.d/unicorn stop", roles: :app
    run "sudo stop #{application}"
    run "sudo stop workers", roles: :worker
    run "sudo stop workers_slow", roles: :worker
    run "sudo stop workers_images", roles: :worker
  end

  desc 'Restart services'
  task :restart, roles: [:app, :worker] do
    run "sudo /etc/init.d/unicorn start || sudo /etc/init.d/unicorn reload", roles: :app
    run "sudo start #{application} || sudo restart #{application} || true"
    # run "sudo start workers || sudo restart workers", roles: :worker
    run "sudo start workers_slow || sudo restart workers_slow", roles: :worker
    run "sudo start workers_images || sudo restart workers_images", roles: :worker
  end

  desc 'Quiet Sidekiq'
  task :quiet, roles: :worker do
    run "sudo pkill --signal USR1 -f '^sidekiq'; true"
  end
end

before 'deploy:update', 'deploy:quiet'
after 'deploy:update', 'foreman:export_procs'
