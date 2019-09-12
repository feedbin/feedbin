namespace :deploy do
  desc "Restart services"
  task :restart do
    on roles :app do
      begin
        execute :sudo, "/etc/init.d/unicorn", :upgrade
      rescue SSHKit::Command::Failed
        execute :sudo, "/etc/init.d/unicorn", :start
      end


      begin
        execute :sudo, :systemctl, :restart, "feedbin.target"
      rescue SSHKit::Command::Failed
        execute :sudo, :systemctl, :start, "feedbin.target"
      end
    end
  end
end
