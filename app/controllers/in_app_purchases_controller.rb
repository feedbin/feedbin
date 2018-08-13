class InAppPurchasesController < ApplicationController
  def show
    @user = current_user
    @billing_event = @user.in_app_purchases.find(params[:id])
    render layout: false
  end
end
