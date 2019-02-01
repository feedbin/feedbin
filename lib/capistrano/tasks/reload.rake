namespace :deploy do
  desc "Reload services"
  task :reload do
    on roles :app do
      invoke "deploy:quiet"
      sleep(5)
      invoke "deploy:restart"
    end
  end
end
