class AppStore::NotificationsV2Controller < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def create
    payload = params[:signedPayload]
    decoded = decode(payload).tap do |data|
      data["data"]["signedTransactionInfo"] = decode(data["data"]["signedTransactionInfo"])
      data["data"]["signedRenewalInfo"] = decode(data["data"]["signedRenewalInfo"])
    end

    logger.info { decoded }
  end

  private

  def decode(data)
    _, payload, _ = data.split(".")
    JSON.load(Base64.decode64(payload))
  end
end
