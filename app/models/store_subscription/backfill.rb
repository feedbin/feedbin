# Makes a StoreSubscription for every subscription the App Store's
# notifications speak of, once, when this table is new. The account is the one
# the latest notification was credited to. A subscription whose account is
# gone is noted on the deleted user instead: it has nobody to belong to.
#
# Apple is asked for the state of any not known to have ended, where there is
# a key to ask with. Accounts are only put on or taken off a plan when
# `apply` is set; without it the result lists who would change.
class StoreSubscription::Backfill
  Result = Struct.new(:created, :noted_on_deleted_users, :without_an_account, :would_lapse, :would_activate, keyword_init: true)

  # except: accounts to leave as they are, whatever their subscriptions say.
  def initialize(apply: false, ask_apple: AppStore::Api.configured?, progress: nil, except: [])
    @apply = apply
    @except = except.map(&:to_i)
    @ask_apple = ask_apple
    @progress = progress
  end

  def run
    result = Result.new(created: 0, noted_on_deleted_users: 0, without_an_account: 0, would_lapse: [], would_activate: [])
    user_ids = Set.new

    transaction_ids.each_with_index do |external_id, index|
      @progress&.call(index + 1, transaction_ids.size)
      next if StoreSubscription.exists?(store: :apple, external_id: external_id)

      notification = latest(external_id)
      state = current_state(notification)
      user = User.find_by_id(notification.user_id)

      if user
        StoreSubscription.create!(state.attributes.merge(store: :apple, external_id: external_id, user: user))
        user_ids << user.id
        result.created += 1
      elsif (deleted_user = DeletedUser.find_by(original_user_id: notification.user_id))
        next unless state.entitling? || state.status == :retrying
        reference = {"store" => "apple", "external_id" => external_id, "product_id" => state.attributes[:product_id]}
        deleted_user.update!(store_subscriptions: (deleted_user.store_subscriptions + [reference]).uniq)
        result.noted_on_deleted_users += 1
      else
        result.without_an_account += 1
      end
    end

    User.where(id: user_ids.to_a - @except).find_each do |user|
      entitled = user.store_subscriptions.entitling.exists?
      result.would_lapse << user.id if !entitled && user.store_plan? && !user.suspended
      result.would_activate << user.id if entitled && (user.suspended || !user.store_plan?) && user.plan.stripe_id != "free"
      user.sync_store_plan if @apply
    end
    result
  end

  private

  def transaction_ids
    @transaction_ids ||= AppStoreNotification.distinct.pluck(:original_transaction_id)
  end

  def latest(external_id)
    AppStoreNotification.where(original_transaction_id: external_id)
      .order(Arel.sql("COALESCE((data->>'signedDate')::bigint, 0) DESC, id DESC")).first
  end

  def current_state(notification)
    recorded = AppStore::SubscriptionState.new(
      transaction: notification.data.safe_dig("data", "signedTransactionInfo"),
      renewal: notification.data.safe_dig("data", "signedRenewalInfo"),
      status: notification.data.safe_dig("data", "status"),
      ended: AppStoreNotificationProcessor::ENDINGS.include?(notification.notification_type),
      environment: notification.data.safe_dig("data", "environment")
    )
    # An ending Apple told us of is an ending; anything else may have moved on since.
    heard_it_end = AppStoreNotificationProcessor::ENDINGS.include?(notification.notification_type) || recorded.status == :revoked
    return recorded if heard_it_end || !@ask_apple

    bundle_id = notification.data.safe_dig("data", "bundleId") || recorded.bundle_id
    AppStore::Api.new(bundle_id: bundle_id, environment: recorded.attributes[:environment]).subscription_state(notification.original_transaction_id) || recorded
  rescue AppStore::Api::Error, HTTP::Error
    recorded
  end
end
