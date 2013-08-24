class SessionsController < ApplicationController

  skip_before_action :authorize

  def new
    @track = true
  end
  
  def create
    @track = true
    user = User.find_by_email(params[:email])
    if user && user.authenticate(params[:password])
      sign_in user, params[:remember_me]
      redirect_back_or root_url
    else
      flash.now.alert = "Invalid email or password"
      render "new"
    end
  end

  def destroy
    sign_out
    redirect_to root_url
  end  
end
