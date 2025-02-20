class PasswordResetsController < ApplicationController
  skip_before_action :authorize

  def new
  end

  def create
    success_message = "Email sent with password reset instructions."
    if user = User.find_by_email(params[:email])
      log(user: user)
      if user.trial_plan?
        success_message = "Email #{ENV["FROM_ADDRESS"]} to request a password reset."
      elsif user.password_reset_sent_at.nil? || user.password_reset_sent_at.before?(1.hour.ago)
        user.send_password_reset
      end
    end
    redirect_to login_url, notice: success_message
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

  def log(user: nil)
    default = "password_reset user=#{params[:email]} ip=#{request.remote_ip}"
    if user
      Rails.logger.error("#{default} created=#{user.created_at.iso8601} subscriptions_count=#{user.subscriptions.count}")
    else
      Rails.logger.error(default)
    end
  end

  def user_params
    params.require(:user).permit(:password)
  end
end
