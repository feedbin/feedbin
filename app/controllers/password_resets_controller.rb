class PasswordResetsController < ApplicationController
  skip_before_action :authorize

  def new
  end

  def create
    success_message = "Email sent with password reset instructions."
    if rate_limited?(10, 5.days)
      redirect_to(login_url, notice: success_message) and return
    end

    if user = User.find_by_email(params[:email])
      if user.password_reset_sent_at.nil? || user.password_reset_sent_at.before?(1.hour.ago)
        user.send_password_reset
      end
      redirect_to login_url, notice: success_message
    else
      redirect_to new_password_reset_path, alert: "Invalid Email Address."
    end
  end

  def edit
    @user = User.find_by_password_reset_token!(Digest::SHA1.hexdigest(params[:id]))
  end

  def update
    @user = User.find_by_password_reset_token!(Digest::SHA1.hexdigest(params[:id]))
    @user.password_reset = true
    @user.password_confirmation = params[:user][:password]
    @user.update_auth_token = true
    if @user.password_reset_sent_at < 2.hours.ago
      redirect_to new_password_reset_path, alert: "Password reset has expired."
    elsif @user.update(user_params)
      redirect_to login_url, notice: "Password has been reset."
      @user.update(password_reset_token: nil)
    else
      render :edit
    end
  end

  private

  def user_params
    params.require(:user).permit(:password)
  end
end
