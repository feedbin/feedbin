class AppsController < ApplicationController
  skip_before_action :verify_authenticity_token

  skip_before_action :authorize
  before_action :basic_auth, only: :login

  def redirect
    if signed_in?
      redirect_to root_url
    else
      head :unauthorized
    end
  end

  def login
    sign_in current_user
    head :ok
  end

  private

  def basic_auth
    authenticate_or_request_with_http_basic("Feedbin") do |username, password|
      @current_user ||= User.where("lower(email) = ?", username.try(:downcase)).take.try(:authenticate, password)
    end
  end
end
