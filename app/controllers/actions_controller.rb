class ActionsController < ApplicationController
  layout 'settings'

  def index
    @user = current_user
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    @authentication_token = CGI::escape(verifier.generate(@user.id))
    @web_service_url = "#{ENV['PUSH_URL']}/apple_push_notifications"
  end

  def new
    @user = current_user
    @action = Action.new
  end

  def create
    @user = current_user
    @action = Action.new(action_params)
    if @action.save
      redirect_to actions_path, notice: 'Action was successfully created.'
    else
      render :new
    end
  end


  private

  def action_params
    params.require(:action_params).permit(:query, :all_feeds, :feed_ids => [], :actions => [])
  end
  
end
