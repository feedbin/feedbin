class AppStore::NotificationsV2Controller < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize
  skip_before_action :set_user
  skip_before_action :honeybadger_context

  def create
    payload = params[:signedPayload]
    valid = JwsVerifier.valid?(payload)
    if valid
      AppStoreNotificationProcessor.perform_async(payload)
      head :ok
    else
      Honeybadger.notify(error_class: "AppStore::NotificationsV2Controller", error_message: "Bad Request", parameters: params, context: {payload: payload})
      head :bad_request
    end
  end
end
