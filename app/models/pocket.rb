class Pocket
  include HTTParty
  base_uri 'https://getpocket.com/v3'
  headers 'Content-Type' => 'application/json; charset=UTF-8', 'X-Accept' => 'application/json'

  def initialize(access_token = nil)
    @access_token = access_token
  end

  def redirect_url(token)
    if token.present?
      uri = URI.parse(self.class.base_uri)
      uri.path = '/auth/authorize'
      uri.query = { 'request_token' => token, 'redirect_uri' => redirect_uri }.to_query
      uri.to_s
    else
      false
    end
  end

  def request_token
    options = {
      body: {consumer_key: ENV['POCKET_CONSUMER_KEY'], redirect_uri: redirect_uri}.to_json
    }
    self.class.post('/oauth/request', options)
  end

  def oauth_authorize(code)
    options = {
      body: {consumer_key: ENV['POCKET_CONSUMER_KEY'], code: code}.to_json
    }
    self.class.post('/oauth/authorize', options)
  end

  def add(url)
    options = {
      body: { url: url, access_token: @access_token, consumer_key: ENV['POCKET_CONSUMER_KEY'] }.to_json
    }
    self.class.post('/add', options).code
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_url('pocket', host: ENV['PUSH_URL'])
  end

end