class AppStore::NotificationsV2Controller < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def create
    logger.info { request.headers.to_h }
    raise
  end
end
