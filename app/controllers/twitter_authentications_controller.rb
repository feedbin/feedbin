class TwitterAuthenticationsController < ApplicationController
  def new
    klass = TwitterApi.new
    response = klass.request_token
    if response.token && response.secret
      session.delete(:twitter_settings_redirect)

      session[:oauth_token]               = response.token
      session[:oauth_secret]              = response.secret
      session[:twitter_settings_redirect] = "true" if params[:mode] == "settings"

      redirect_to response.authorize_url
    else
      Honeybadger.notify(
        error_class: "SupportedSharingServicesController#oauth_request",
        error_message: "#{service_info[:label]} failure",
        parameters: {response: response}
      )
      redirect_to settings_url, notice: "Unknown Twitter error."
    end
  rescue OAuth => e
    Honeybadger.notify(
      error_class: "TwitterApis#new",
      error_message: "Twitter failure",
      parameters: {exception: e}
    )
    redirect_to settings_url, alert: "Unknown Twitter error."
  end

  def save
    @user = current_user
    klass = TwitterApi.new
    if klass.response_valid?(session, params)
      access_token = klass.request_access(session.delete(:oauth_token), session.delete(:oauth_secret), params[:oauth_verifier])
      @user.update(
        twitter_access_token: access_token.token,
        twitter_access_secret: access_token.secret,
        twitter_screen_name: access_token.params[:screen_name],
        twitter_auth_failures: 0
      )

      if session.delete(:twitter_settings_redirect)
        redirect_to settings_newsletters_pages_url, notice: "Twitter has been activated!"
      elsif query = session.delete(:subscribe_query)
        redirect_to subscribe_url(subscribe: query)
      else
        redirect_to settings_url, notice: "Twitter has been activated!"
      end
    else
      if session.delete(:twitter_settings_redirect)
        redirect_to settings_newsletters_pages_url, alert: "Feedbin needs your permission to activate Twitter."
      else
        redirect_to root_url, alert: "Feedbin needs your permission to activate Twitter."
      end
    end
  rescue OAuth => e
    Honeybadger.notify(
      error_class: "TwitterApisController#save",
      error_message: "Twitter failure",
      parameters: {exception: e}
    )
    redirect_to settings_url, alert: "Unknown Twitter error."
  end

  def delete
    @user.twitter_log_out
    redirect_to settings_newsletters_pages_url, notice: "Twitter has been deactivated."
  end
end
