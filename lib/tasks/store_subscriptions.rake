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

  desc "Development only: puts purchase-test@example.com on a fresh trial, clears what Xcode's test store left on this server, and prints the account's id."
  task test_account: :environment do
    abort "Only on a development server." unless Rails.env.development?
    trial = Plan.find_by_stripe_id!("trial")
    user = User.find_or_initialize_by(email: "purchase-test@example.com")
    if user.new_record?
      password = SecureRandom.hex
      user.assign_attributes(password: password, password_confirmation: password, api_v3: "1", plan: trial)
      user.update_auth_token = true
      user.save!
    end
    # Xcode numbers its test transactions from zero each time, so the last run's rows would be taken for this one's.
    stale = StoreSubscription.where(user: user).or(StoreSubscription.where(environment: "xcode"))
    owners = User.where(id: stale.select(:user_id)).where.not(id: user.id).to_a
    stale.delete_all
    owners.each(&:sync_store_plan)
    AppStoreNotification.where(user_id: user.id).delete_all
    user.update_columns(plan_id: trial.id, suspended: false, expires_at: 30.days.from_now)
    puts user.id
  end

  desc "Development only: what the server holds for purchase-test@example.com."
  task test_account_status: :environment do
    abort "Only on a development server." unless Rails.env.development?
    user = User.find_by!(email: "purchase-test@example.com")
    subscriptions = user.store_subscriptions.map { "#{_1.product_id} #{_1.status} (#{_1.environment})" }
    puts "plan #{user.plan.stripe_id}#{user.suspended ? ", suspended" : ""}; subscriptions: #{subscriptions.presence&.join(", ") || "none"}"
  end
end
