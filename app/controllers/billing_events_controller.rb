class BillingEventsController < ApplicationController

  before_action :user_owns_event

  def show
    @user = current_user
    @billing_event = BillingEvent.find(params[:id])
    @user = @billing_event.billable

    respond_to do |format|
      format.html { render layout: false }
    end
  end

  private

  def user_owns_event
    unless current_user.billing_events.where(billing_events: {id: params[:id]}).present?
      render_404
    end
  end

end
