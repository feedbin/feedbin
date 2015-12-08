namespace :deploy do
  desc 'Commands for unicorn application'
  task :restart do
    execute :sudo :restart :workers
  end
end