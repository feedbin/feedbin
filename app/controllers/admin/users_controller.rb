class Admin::UsersController < ApplicationController
  def index
    if params.has_key?(:q)
      @users = User.page(params[:page]).where("email ILIKE :query", query: "%#{params[:q]}%") + DeletedUser.page(params[:page]).where("email ILIKE :query", query: "%#{params[:q]}%")
    else
      @users = User.page(params[:page]) + DeletedUser.page(params[:page])
    end
    render layout: "settings"
  end

  def destroy
    @user = User.find(params[:id])
    @user.deleted = true
    UserDeleter.perform_async(@user.id)
  end

  def authorize
    unless current_user.try(:admin?)
      render_404
    end
  end
end
