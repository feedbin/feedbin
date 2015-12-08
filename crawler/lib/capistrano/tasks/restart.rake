namespace :deploy do
  desc 'Commands for unicorn application'
  task :restart do
    on roles :all do
      begin
        execute :sudo, :restart, :workers
      rescue SSHKit::Command::Failed
        execute :sudo, :start, :workers
      end
    end
  end
end