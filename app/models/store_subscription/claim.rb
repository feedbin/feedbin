# An account presenting the subscription its store account holds: the signed
# transaction is the proof, and Apple's own API is asked for the state where
# it can be.
class StoreSubscription::Claim
  class Invalid < StandardError; end

  def initialize(user, signed_transaction:)
    @user = user
    @signed_transaction = signed_transaction
  end

  def run
    subscription = StoreSubscription.record(state, user: @user)
    settle(subscription)
  end

  # Moves a subscription that is live on another account to this one.
  def take
    subscription = StoreSubscription.find_by(store: state.store, external_id: state.external_id)
    return run if subscription.nil? || subscription.user == @user

    subscription.move_to(@user)
    subscription.apply(state)
    settle(subscription)
  end

  private

  def settle(subscription)
    AppStoreNotification.where(original_transaction_id: subscription.external_id, user_id: nil).update_all(user_id: @user.id)
    AppStoreAccountTokenUpdate.perform_async(subscription.id) unless state.app_account_token&.downcase == @user.app_account_token&.downcase
    StoreSubscriptionRefresh.perform_async(subscription.id) unless @verified_with_store
    subscription
  end

  def state
    @state ||= from_store || AppStore::SubscriptionState.new(transaction: transaction)
  end

  def transaction
    @transaction ||= AppStore::SignedPayload.decode(@signed_transaction).tap do |claims|
      raise Invalid, "The transaction is not a subscription of a Feedbin app." unless claims["originalTransactionId"] && self.class.bundle_ids.include?(claims["bundleId"])
    end
  rescue AppStore::SignedPayload::Invalid => error
    raise Invalid, error.message
  end

  # Apple's answer is newer than anything the device holds. Without it (no
  # key here, or Apple unreachable) the transaction stands, and a job asks.
  def from_store
    return nil unless AppStore::Api.configured?
    environment = transaction["environment"] || "Production"
    AppStore::Api.new(bundle_id: transaction["bundleId"], environment: environment).subscription_state(transaction["originalTransactionId"]).tap do |state|
      @verified_with_store = state.present?
    end
  rescue AppStore::Api::Error, HTTP::Error, OpenSSL::OpenSSLError
    nil
  end

  def self.bundle_ids
    Feedbin::Application.config.app_store_bundle_ids
  end
end
