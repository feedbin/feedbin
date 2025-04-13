class MutesController < ApplicationController
  layout "settings"

  before_action :set_action, only: [:destroy]

  def index
    @mutes = @user.actions.mute.natural_sort_by { |action| action.title }
  end

  def create
    @action = @user.actions.new(
      query: params[:query],
      all_feeds: params[:all_feeds] == "true" ? true : false,
      feed_ids: [params[:feed_id]],
      action_type: Action.action_types[:mute],
      actions: ["mark_read"],
      apply_action: "1"
    )

    if @action.save
      flash[:notice] = "Mute was successfully created."
    else
      flash[:error] = @action.errors.full_messages.join(". ")
    end
    flash.discard
  end

  def destroy
    @action.destroy
    respond_to do |format|
      format.html do
        redirect_to actions_url, notice: "Mute deleted."
      end
      format.js do
        @mutes = @user.actions.mute.natural_sort_by { |action| action.title }
        flash[:notice] = "Mute deleted."
        flash.discard
      end
    end
  end

  private

  def set_action
    @action = @user.actions.find(params[:id])
  end
end
