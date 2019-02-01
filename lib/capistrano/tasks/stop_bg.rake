namespace :deploy do
  desc "Stop services"
  task :stop_bg do
    on roles :app do
      invoke "deploy:quiet"

      sleep(10)

      processes = [:clock, :workers, :workers_slow, :workers_low]

      processes.each do |process|
        execute :sudo, :stop, process
      rescue SSHKit::Command::Failed
      end
    end
  end
end
