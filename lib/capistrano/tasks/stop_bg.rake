namespace :deploy do
  desc "Stop services"
  task :stop_bg do
    on roles :app do
      invoke "deploy:quiet"
      sleep(10)
      execute :sudo, :systemctl, :stop, "feedbin.target"
      execute "/etc/init.d/unicorn", :stop
    end
  end
end
