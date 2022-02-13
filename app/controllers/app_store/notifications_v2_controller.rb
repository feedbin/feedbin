class AppStore::NotificationsV2Controller < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize
  skip_before_action :set_user
  skip_before_action :honeybadger_context

  def create
    payload = params[:signedPayload]
    valid = JwsVerifier.valid?(payload)
    AppStoreNotificationProcessor.perform_async(payload) if valid
    head valid ? :ok : :not_found
  end
end
