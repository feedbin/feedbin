class BillingEventsController < ApplicationController
  def show
    @user = current_user
    @billing_event = @user.billing_events.where(event_type: "charge.succeeded").find(params[:id])
    render layout: false
  end
end
