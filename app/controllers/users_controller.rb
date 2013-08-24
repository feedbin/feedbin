class UsersController < ApplicationController
  skip_before_action :authorize, only: [:new, :create]
  
  before_action :set_user, only: [:update, :destroy]
  before_action :ensure_permission, only: [:update, :destroy]

  def new
    @track = true
    @user = User.new
    if params[:coupon]
      @coupon = Coupon.where(coupon_code: params[:coupon]).first
      @coupon_valid = @coupon.present? && !@coupon.redeemed
      @user.coupon_code = params[:coupon]
    end
    if !ENV['STRIPE_API_KEY'] || params[:coupon]
      @user.plan_id = Plan.find_by_stripe_id('free').id
    end
  end
  
  def create
    @user = User.new(user_params)
    @user.update_auth_token = true
    if params[:user] && params[:user][:password]
      @user.password_confirmation = params[:user][:password]
    end
    if @user.save
      sign_in @user
      redirect_to root_url
    else
      render "new"
    end
  end

  def update
    @user.update_auth_token = true
    @user.old_password_valid = @user.authenticate(params[:user][:old_password])
    @user.free_ok = (@user.plan.stripe_id == 'free')
    @user.attributes = user_params
    if params[:user] && params[:user][:password]
      @user.password_confirmation = params[:user][:password]
    end
    if @user.save
      sign_in @user
      redirect_to settings_account_path, notice: 'Account updated.'
    else
      redirect_to settings_account_path, alert: @user.errors.full_messages.join('. ') + '.'
    end
  end  
  
  def destroy
    @user.destroy
    redirect_to root_url
  end
  
  private

  def set_user
    @user = current_user
  end
  
  def ensure_permission
    unless @user.id == current_user.id || current_user.admin
      render_404
    end
  end
  
  def user_params
    params.require(:user).permit(:email, :password, :stripe_token, :coupon_code, :plan_id)
  end
  
    
end
