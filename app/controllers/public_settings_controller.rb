class PublicSettingsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def email_unsubscribe
    user = Rails.application.message_verifier(:unsubscribe).verify(params[:id])
    @user = User.find(user)
    @user.update(marketing_unsubscribe: "1")
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    render_404
  end

  def account_closed
  end
end
