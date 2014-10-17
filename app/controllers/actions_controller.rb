class ActionsController < ApplicationController
  layout 'settings'

  def index
    @user = current_user
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    @authentication_token = CGI::escape(verifier.generate(@user.id))
    @web_service_url = "#{ENV['PUSH_URL']}/apple_push_notifications"
  end

  def new
    @user = current_user
    @action = Action.new
  end

end
