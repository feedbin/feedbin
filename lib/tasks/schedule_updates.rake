namespace :feeds do
    desc "Schedule feed updates"
    task schedule_updates: :environment do
      require 'sidekiq/api'
      feeds_lists = Feed.all
      feeds_lists.each do |feed|
        p "#{feed.id}"
        # Insert elements to "utility" Sidekiq queue
        Sidekiq::Client.push(
        'queue' => :utility,
        'class' => FeedUpdate, 
        'args' => [feed.id] 
        )
      end
    end
  end
  
 # Programa la actualización de los feeds cada 30 minutos
      #Sidekiq::Cron::Job.create(
      #  name: "ScheduleAll",
      #  cron: "*/30 * * * *", # Ejecutar cada 30 minutos
      #  class: "FeedCrawler::ScheduleAll"
      #)
