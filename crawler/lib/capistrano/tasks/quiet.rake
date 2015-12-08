namespace :deploy do
  desc 'Commands for unicorn application'
  task :quiet do
    puts capture("sudo pkill --signal USR1 -f '^sidekiq'")
  end
end