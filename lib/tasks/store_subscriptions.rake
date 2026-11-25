namespace :store_subscriptions do
  # In this order, once, when the table is new:
  #   1. store_subscriptions:backfill            makes the rows, and says who would lapse or be activated
  #   2. store_subscriptions:replay              takes in the notifications that died in Sidekiq
  #   3. store_subscriptions:backfill APPLY=1    lapses and activates
  # Replay comes before APPLY: an account whose subscription Apple began afresh looks lapsed until the
  # notifications for the new one, which died for want of a token, have been taken in.
  desc "Make store subscriptions from the App Store's notifications. APPLY=1 also puts accounts on, or takes them off, a plan; without it the task says who would change."
  task backfill: :environment do
    progress = ->(index, total) { puts "#{index}/#{total}" if (index % 50).zero? || index == total }
    result = StoreSubscription::Backfill.new(apply: ENV["APPLY"].present?, progress: progress).run
    puts "created: #{result.created}"
    puts "noted on deleted users: #{result.noted_on_deleted_users}"
    puts "with no account at all: #{result.without_an_account}"
    puts "#{ENV["APPLY"].present? ? "lapsed" : "would lapse"}: #{result.would_lapse.inspect}"
    puts "#{ENV["APPLY"].present? ? "activated" : "would activate"}: #{result.would_activate.inspect}"
  end

  desc "Process again the App Store notifications that failed in Sidekiq (its retry and dead sets), oldest first, and take them out of those sets."
  task replay: :environment do
    require "sidekiq/api"
    jobs = [Sidekiq::RetrySet.new, Sidekiq::DeadSet.new].flat_map { |set| set.select { _1.klass == "AppStoreNotificationProcessor" } }
    jobs.sort_by { _1["failed_at"].to_f }.each do |job|
      AppStoreNotificationProcessor.new.perform(*job.args)
      job.delete
    end
    puts "replayed: #{jobs.size}"
    puts "still held by no account: #{AppStoreNotification.where(user_id: nil).distinct.count(:original_transaction_id)}"
  end
end
