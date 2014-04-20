class Tumblr
  URL = "http://www.tumblr.com"
  API_URL = "https://api.tumblr.com/v2"

  # 1. tumblr = Tumblr.new
  # 2. client = tumblr.request_token
  # 3. session[:tumblr_token] = client.token; session[:tumblr_secret] = client.secret
  # 4. redirect_to client.authorize_url
  # 5. tumblr = Tumblr.new
  # 6. access_token = tumblr.request_access(session[:tumblr_token], session[:tumblr_secret], params[:oauth_verifier])
  # 7. save access_token.token and access_token.secret in the database

  def initialize(consumer_key = nil, consumer_secret = nil)
    if consumer_secret && consumer_secret
      @client = OAuth::AccessToken.new(consumer, consumer_key, consumer_secret)
    end
  end

  def consumer
    options = {
      site: URL,
      request_token_path: '/oauth/request_token',
      authorize_path: '/oauth/authorize',
      access_token_path: '/oauth/access_token',
      http_method: :post
    }
    OAuth::Consumer.new(ENV['TUMBLR_KEY'], ENV['TUMBLR_SECRET'], options)
  end

  def request_token
    consumer.get_request_token(oauth_callback: redirect_uri)
  end

  def request_access(oauth_token, oauth_token_secret, oauth_verifier)
    params = {oauth_token: oauth_token, oauth_token_secret: oauth_token_secret, }
    client = OAuth::RequestToken.from_hash(consumer, params)
    client.get_access_token(oauth_verifier: oauth_verifier)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_supported_sharing_service_url('tumblr', host: ENV['PUSH_URL'])
  end

  def user_info
    result = @client.get("#{API_URL}/user/info")
    JSON.load(result.body)
  end


end
# 8cOe317D8DHNhy6ZzjUrzjVS618l3JBo6Ayz5QfQnkXVerMdHf
#
# Getting an Access Token with OAuth-Ruby and Tumblr API (Rails 3)
# #0. provided when registering application
#
# if @consumer
#   #1. get a request token
#   @request_token = @consumer.get_request_token;
#   session[:request_token] = @request_token
#   session[:tumblog] = @tumblog
#
#   #2. have the user authorize
#   redirect_to @request_token.authorize_url
# else
#   flash[:error] = "Failed to acquire request token from Tumblr."
#   render 'new'
# end
#
# if params[:oauth_token] && params[:oauth_verifier]
#   @tumblog = session[:tumblog]
#   @request_token = session[:request_token]
#
#   #3. get an access token
#   @access_token = @request_token.get_access_token
#
#   . . . .
# end
#
# @access_token = @request_token.get_access_token
#
# require 'rubygems'
# require 'oauth'
#
# CONSUMER_KEY = 'YOUR_CONSUMER_KEY'
# CONSUMER_SECRET = 'YOUR_CONSUMER_SECRET'
#
# consumer = OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET, :site => 'https://www.tumblr.com/oauth/access_token')
# access_token = consumer.get_access_token(nil, {}, { :x_auth_mode => 'client_auth',
#                                                     :x_auth_username => "some@email.com",
#                                                     :x_auth_password => "password"})
# tumblr_credentials = access_token.get('http://www.tumblr.com/api/authenticate')
#
# puts access_token
# puts access_token.token
# puts access_token.secret
# puts tumblr_credentials.body