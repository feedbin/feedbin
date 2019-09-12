namespace :deploy do
  desc "Restart services"
  task :restart do
    on roles :app do
      execute "/etc/init.d/unicorn", :upgrade
      begin
        execute :sudo, :systemctl, :restart, "feedbin.target"
      rescue SSHKit::Command::Failed
        execute :sudo, :systemctl, :start, "feedbin.target"
      end
    end
  end
end
