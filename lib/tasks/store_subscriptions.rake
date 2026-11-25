namespace :store_subscriptions do
  # In this order, once, when the table is new:
  #   1. store_subscriptions:backfill            makes the rows, and says who would lapse or be activated
  #   2. store_subscriptions:replay              takes in the notifications that died in Sidekiq
  #   3. store_subscriptions:backfill APPLY=1    lapses and activates
  # Look at who step 1 says would lapse before step 3: a subscription the server never placed (bought with
  # no token) leaves its account looking unpaid. EXCEPT=51532,162401 leaves accounts as they are: those two
  # were paying through subscriptions on other Apple Accounts in November 2026, attached to nobody, and
  # were to keep their service (QUESTIONS.md 193 in feedbin-ios-reflex).
  desc "Make store subscriptions from the App Store's notifications. APPLY=1 also puts accounts on, or takes them off, a plan; without it the task says who would change. EXCEPT=1,2 leaves those accounts alone."
  task backfill: :environment do
    progress = ->(index, total) { puts "#{index}/#{total}" if (index % 50).zero? || index == total }
    result = StoreSubscription::Backfill.new(apply: ENV["APPLY"].present?, progress: progress, except: ENV["EXCEPT"].to_s.split(",")).run
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
