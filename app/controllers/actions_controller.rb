class ActionsController < ApplicationController

  def index
    @user = current_user
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    @authentication_token = CGI::escape(verifier.generate(@user.id))
    @web_service_url = "#{ENV['PUSH_URL']}/apple_push_notifications"
    render layout: 'settings'
  end

  def actions_update
    @user = current_user
    @user.free_ok = (@user.plan.stripe_id == 'free')
    if @user.update_attributes(actions_update_params)
      redirect_to actions_url, notice: "Actions updated."
    else
      @messages = ['Error saving services.']
      flash[:error] = render_to_string partial: "shared/messages"
      redirect_to actions_url
    end
  end

  private

  def actions_update_params
    all_feeds = @user.subscriptions.pluck(:feed_id)
    if params[:user][:actions_attributes]
      owned_actions = @user.actions.pluck(:id)
      requested_actions = params[:user][:actions_attributes].collect { |index, actions| {index: index, id: actions['id']} }
      requested_actions.each do |service|
        next if service[:index] =~ /_insert$/
        unless owned_actions.include?(service[:id].to_i)
          params[:user][:actions_attributes].delete(service[:index])
        end
      end
      params[:user][:actions_attributes].map do |index, actions|
        params[:user][:actions_attributes][index] = actions.slice(:id, :query, :actions, :feed_ids, :all_feeds, :_destroy)
        if actions[:all_feeds] == '1'
          params[:user][:actions_attributes][index][:feed_ids] = all_feeds
        end
      end
    end
    params.require(:user).permit!
  end

end
