# A subscription Apple or Google bills, and the account it pays for. The store
# is the authority on its state; this row is the last thing the store said.
class StoreSubscription < ApplicationRecord
  # The other account's subscription is live, so it is not ours to take.
  class OwnedByAnotherAccount < StandardError
    attr_reader :subscription

    def initialize(subscription)
      @subscription = subscription
      super("The subscription belongs to another account.")
    end
  end

  class MovedTooRecently < StandardError; end

  MOVE_INTERVAL = 30.days

  PRODUCTS = {
    "yearly_v1"         => {plan: "app-subscription", period: "yearly"},
    "yearly_pro_v1"     => {plan: "app-subscription", period: "yearly"},
    "monthly_pro_v1"    => {plan: "app-subscription", period: "monthly"},
    "yearly_podcast_v1" => {plan: "podcast-subscription", period: "yearly"},
    "yearly_podcast_v2" => {plan: "podcast-subscription", period: "yearly"},
    "yearly_podcast_v3" => {plan: "podcast-subscription", period: "yearly"},
    "yearly_podcast_v4" => {plan: "podcast-subscription", period: "yearly"}
  }.freeze
  DEFAULT_PRODUCT = {plan: "app-subscription", period: nil}.freeze

  # Where the person who pays manages it: nobody else can cancel it for them.
  STORES = {
    "apple" => {name: "the App Store", manage_url: "https://apps.apple.com/account/subscriptions"},
    "google" => {name: "Google Play", manage_url: "https://play.google.com/store/account/subscriptions"}
  }.freeze

  belongs_to :user

  enum :store, {apple: 0, google: 1}
  # retrying: the store is still trying to collect, with no service meanwhile.
  enum :status, {active: 0, grace: 1, retrying: 2, expired: 3, revoked: 4}

  scope :entitling, -> { where(status: [:active, :grace]) }
  # Past its date with nothing heard since: the store is asked directly.
  scope :overdue, -> { where(status: [:active, :grace, :retrying]).where(expires_at: ..1.hour.ago) }

  # Records what the store said about a subscription, for the account that
  # presented it (`user`), or for whoever holds it when the store itself is
  # the one telling us. Returns the subscription, or nil when there is neither
  # a row nor an account to give it to.
  #
  # A subscription that has lapsed goes to whoever buys it again, and stays
  # where it is when another account only shows it. A live one is not another
  # account's to present: that raises.
  def self.record(state, user: nil)
    transaction do
      subscription = lock.find_by(store: state.store, external_id: state.external_id)
      return nil if subscription.nil? && user.nil?

      subscription ||= new(store: state.store, external_id: state.external_id, user: user)
      previous_owner = subscription.user if subscription.persisted?

      if user && previous_owner && previous_owner != user && state.entitling?
        raise OwnedByAnotherAccount.new(subscription) if subscription.entitling?
        subscription.user = user
      end

      subscription.apply(state)
      previous_owner.sync_store_plan if previous_owner && previous_owner != subscription.user
      subscription.user.sync_store_plan
      subscription
    end
  end

  # Newer news only: notifications can arrive out of order.
  def apply(state)
    return self if persisted? && !user_id_changed? && signed_at && state.signed_at && state.signed_at < signed_at
    update!(state.attributes)
    self
  end

  # Gives a live subscription to another account, at that account's asking.
  def move_to(new_user)
    raise MovedTooRecently if moved_at&.after?(MOVE_INTERVAL.ago)

    previous_owner = user
    transaction do
      update!(user: new_user, moved_at: Time.current)
      previous_owner.sync_store_plan
      new_user.sync_store_plan
    end
    UserMailer.store_subscription_moved(previous_owner.id, store).deliver_later
    AppStoreAccountTokenUpdate.perform_async(id) if apple?
    self
  end

  def movable_at
    moved_at && moved_at + MOVE_INTERVAL
  end

  def entitling?
    active? || grace?
  end

  def product
    PRODUCTS.fetch(product_id, DEFAULT_PRODUCT)
  end

  def plan
    Plan.find_by_stripe_id(product[:plan])
  end

  def period
    product[:period]
  end

  def price
    price_milliunits && price_milliunits / 1000.0
  end

  # What a deleted account keeps of it, so a later renewal can be answered.
  def reference
    {store: store, external_id: external_id, product_id: product_id}
  end
end
