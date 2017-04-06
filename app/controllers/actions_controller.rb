class ActionsController < ApplicationController

  layout "settings"

  before_action :set_action, only: [:edit, :update, :destroy]

  def index
    @authentication_token = authentication_token(@user)
    @web_service_url = "#{ENV['PUSH_URL']}/apple_push_notifications"
    @actions = @user.actions.where("action_type <> ?", Action.action_types[:notifier])
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

  def authentication_token(user)
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    CGI::escape(verifier.generate(user.id))
  end

  def action_params
    params.require(:action_params).permit(:query, :all_feeds, :title, :feed_ids => [], :actions => [], :tag_ids => [])
  end

  def set_action
    @action = @user.actions.find(params[:id])
  end

end
