# Tells Apple which account a subscription pays for now, so the token its
# later transactions and notifications carry is that account's.
class AppStoreAccountTokenUpdate
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(id)
    subscription = StoreSubscription.find_by_id(id)
    token = subscription&.user&.app_account_token
    return unless subscription&.apple? && token && AppStore::Api.configured?

    AppStore::Api.new(bundle_id: subscription.app_identifier, environment: subscription.environment).set_app_account_token(subscription.external_id, token)
  end
end
