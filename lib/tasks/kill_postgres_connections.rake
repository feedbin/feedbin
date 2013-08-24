task :kill_postgres_connections => :environment do
  unless ENV['HEROKU_APP']
    db_name = "#{File.basename(Rails.root)}_#{Rails.env}"
    sh = "ps xa | grep postgres: | grep #{db_name} | grep -v grep | awk '{print $1}' | xargs kill"
    puts `#{sh}`
  end
end
task "db:drop" => :kill_postgres_connections