class AppsController < ApplicationController
  skip_before_action :verify_authenticity_token

  skip_before_action :authorize

  def redirect
    if signed_in?
      redirect_to root_url
    else
      head :unauthorized
    end
  end

  def login
    if user = authenticate_with_http_basic { |username, password| User.where("lower(email) = ?", username.try(:downcase)).take.try(:authenticate, password) }
      sign_in user
      head :ok
    else
      request_http_basic_authentication
    end
  end
end
