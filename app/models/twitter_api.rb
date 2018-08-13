class TwitterAPI
  API_URL = "https://api.twitter.com"

  # 1. twitter = Twitter.new
  # 2. client = twitter.request_token
  # 3. session[:tumblr_token] = client.token; session[:twitter_secret] = client.secret
  # 4. redirect_to client.authorize_url
  # 5. twitter = Twitter.new
  # 6. access_token = twitter.request_access(session[:twitter_token], session[:twitter_secret], params[:oauth_verifier])
  # 7. save access_token.token and access_token.secret in the database

  def consumer
    options = {
      site: API_URL,
      request_token_path: "/oauth/request_token",
      authorize_path: "/oauth/authorize",
      access_token_path: "/oauth/access_token",
      http_method: :post,
    }
    OAuth::Consumer.new(ENV["TWITTER_KEY"], ENV["TWITTER_SECRET"], options)
  end

  def request_token
    consumer.get_request_token(oauth_callback: redirect_uri)
  end

  def request_access(oauth_token, oauth_token_secret, oauth_verifier)
    params = {oauth_token: oauth_token, oauth_token_secret: oauth_token_secret}
    client = OAuth::RequestToken.from_hash(consumer, params)
    client.get_access_token(oauth_verifier: oauth_verifier)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.save_twitter_authentications_url(host: ENV["PUSH_URL"])
  end

  def response_valid?(session, params)
    params[:oauth_verifier].present?
  end
end
