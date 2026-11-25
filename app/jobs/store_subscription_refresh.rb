# Asks the store what a subscription's state is now. With no id, queues every
# subscription that has passed its date with nothing heard since: a
# notification can be lost, and the store is the authority.
class StoreSubscriptionRefresh
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(id = nil)
    return StoreSubscription.overdue.pluck(:id).each { self.class.perform_async(_1) } if id.nil?

    subscription = StoreSubscription.find_by_id(id)
    return unless subscription&.apple? && AppStore::Api.configured?

    state = AppStore::Api.new(bundle_id: subscription.app_identifier, environment: subscription.environment).subscription_state(subscription.external_id)
    StoreSubscription.record(state) if state
  end
end
