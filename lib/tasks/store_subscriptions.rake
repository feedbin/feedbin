namespace :store_subscriptions do
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
end
