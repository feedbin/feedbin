namespace :deploy do
  desc 'Stop services'
  task :stop_bg do
    on roles :all do

      invoke "deploy:quiet"

      sleep(10)

      begin
        execute :sudo, :stop, :workers
      rescue SSHKit::Command::Failed
      end

    end
  end
end