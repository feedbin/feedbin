class Admin::UsersController < ApplicationController
  def index

    if params.has_key?(:q)
      @users = User.page(params[:page]).where("email LIKE :query", query: "%#{params[:q]}%")  + DeletedUser.page(params[:page]).where("email LIKE :query", query: "%#{params[:q]}%")
    else
      @users = User.page(params[:page]) + DeletedUser.page(params[:page])
    end
    render layout: 'settings'
  end

  def show
    @user = User.find(params[:id])
    @billing_events = @user.billing_events.where(event_type: 'charge.succeeded')
    @billing_events = @billing_events.to_a.sort_by {|billing_event| -billing_event.details.data.object.created }
    render layout: 'settings'
  end

  def authorize
    unless current_user.try(:admin?)
      render_404
    end
  end

end
