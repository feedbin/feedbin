namespace :deploy do
  desc "Restart services"
  task :restart do
    on roles :app do
      begin
        execute :sudo, "/etc/init.d/unicorn", :start
      rescue SSHKit::Command::Failed
        execute :sudo, "/etc/init.d/unicorn", :reload
      end

      begin
        execute :sudo, :restart, :clock
      rescue SSHKit::Command::Failed
        execute :sudo, :start, :clock
      end

      begin
        execute :sudo, :restart, :workers
      rescue SSHKit::Command::Failed
        execute :sudo, :start, :workers
      end

      begin
        execute :sudo, :restart, :workers_slow
      rescue SSHKit::Command::Failed
        execute :sudo, :start, :workers_slow
      end

      begin
        execute :sudo, :restart, :workers_low
      rescue SSHKit::Command::Failed
        execute :sudo, :start, :workers_low
      end
    end
  end
end
