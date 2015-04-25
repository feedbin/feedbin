class ActionsController < ApplicationController

  layout "settings"

  before_action :set_action, only: [:edit, :update, :destroy]

  def index
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    @authentication_token = CGI::escape(verifier.generate(@user.id))
    @web_service_url = "#{ENV['PUSH_URL']}/apple_push_notifications"
    @actions = @user.actions
  end

  def new
    @action = @user.actions.new
  end

  def edit
  end

  def create
    @action = @user.actions.new(action_params)
    if @action.save
      redirect_to actions_url, notice: "Action was successfully created."
    else
      render :new
    end
  end

  def update
    if @action.update(action_params)
      redirect_to actions_url, notice: "Action was successfully updated."
    else
      render :edit
    end
  end

  def destroy
    @action.destroy
    redirect_to actions_url, notice: "Action was successfully deleted."
  end

  private

  def action_params
    params.require(:action_params).permit(:query, :all_feeds, :title, :feed_ids => [], :actions => [], :tag_ids => [])
  end

  def set_action
    @action = @user.actions.find(params[:id])
  end

end
