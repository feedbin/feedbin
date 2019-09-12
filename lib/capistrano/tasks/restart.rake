namespace :deploy do
  desc "Restart services"
  task :restart do
    on roles :app do
      execute :service, :unicorn, :upgrade
      begin
        execute :sudo, :service, "feedbin.target", :restart
      rescue SSHKit::Command::Failed
        execute :sudo, :service, "feedbin.target", :start
      end
    end
  end
end
