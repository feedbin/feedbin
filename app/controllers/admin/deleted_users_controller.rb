class Admin::DeletedUsersController < Admin::ApplicationController
  before_action :set_deleted_user

  # What a closed account left behind that a store may still be billing.
  def show
    render layout: "settings"
  end

  private

  def set_deleted_user
    @deleted_user = DeletedUser.find(params[:id])
  end
end
