class SessionsController < ApplicationController
  skip_before_action :authorize

  def new
    redirect_to root_url if signed_in?
  end

  def create
    user = User.where("lower(email) = ?", params[:email].try(:strip).try(:downcase)).take
    if user&.authenticate(params[:password])
      sign_in user, params[:remember_me]

      if request.xhr?
        render js: "window.location = '#{root_url}';"
      else
        redirect_back_or root_url
      end
    else
      flash.now.alert = "Invalid email or password"
      render "new", status: :unauthorized
    end
  end

  def destroy
    sign_out
    redirect_to root_url
  end

  def refresh
    head :ok
  end
end
