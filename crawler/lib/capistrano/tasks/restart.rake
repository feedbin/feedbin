namespace :deploy do
  desc 'Restart refresher processes'
  task :restart do
    on roles :all do
      begin
        execute :sudo, :systemctl, :restart, "refresher.target"
      rescue SSHKit::Command::Failed
        execute :sudo, :systemctl, :start, "refresher.target"
      end
    end
  end
end