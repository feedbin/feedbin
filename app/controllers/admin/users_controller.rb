class Admin::UsersController < ApplicationController
  def index
    # Relation#+ is Array#+: it loads both relations and returns a plain Array,
    # which drops the pagination metadata the view needs to offer a next page.
    # Paginate the two lists separately so each keeps its own.
    users = User.all
    deleted_users = DeletedUser.all

    if params.key?(:q)
      # Without escaping, a % or _ an operator types acts as a wildcard.
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
      users = users.where("email ILIKE :query", query: pattern)
      deleted_users = deleted_users.where("email ILIKE :query", query: pattern)
    end

    @users = users.page(params[:page])
    @deleted_users = deleted_users.page(params[:page])
    render layout: "settings"
  end

  def destroy
    @user = User.find(params[:id])
    @user.deleted = true
    UserDeleter.perform_async(@user.id)
  end

  def reset_password
    user = User.find(params[:id])
    user.setting_on!(:password_resettable)
    user.send_password_reset
  end

  def authorize
    unless current_user.try(:admin?)
      render_404
    end
  end
end
