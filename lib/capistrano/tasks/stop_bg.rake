namespace :deploy do
  desc "Stop services"
  task :stop_bg do
    on roles :app do
      invoke "deploy:quiet"
      sleep(10)
      execute :sudo, :service, "feedbin.target", :stop
    end
  end
end
