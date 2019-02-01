class Share::Pocket < Share::Service
  include HTTParty
  base_uri "https://getpocket.com"
  headers "Content-Type" => "application/json; charset=UTF-8", "X-Accept" => "application/json"

  PATHS = {
    auth_authorize: "/auth/authorize",
    oauth_request: "/v3/oauth/request",
    oauth_authorize: "/v3/oauth/authorize",
    add: "/v3/add",
  }

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @access_token = @klass.access_token
    end
  end

  def authorize_url(token)
    if token.present?
      uri = url_for(:auth_authorize)
      uri.query = {"request_token" => token, "redirect_uri" => redirect_uri}.to_query
      uri.to_s
    else
      false
    end
  end

  def request_token
    options = {
      body: {consumer_key: ENV["POCKET_CONSUMER_KEY"], redirect_uri: redirect_uri}.to_json,
    }
    response = self.class.post(PATHS[:oauth_request], options)
    if response.code == 200
      code = response.parsed_response["code"]
      OpenStruct.new(token: code, secret: code, authorize_url: authorize_url(code))
    end
  end

  def authorize(code)
    options = {
      body: {consumer_key: ENV["POCKET_CONSUMER_KEY"], code: code}.to_json,
    }
    self.class.post(PATHS[:oauth_authorize], options)
  end

  def response_valid?(session, params)
    response = authorize(session[:oauth_token])
    valid = false
    if response.code == 200
      valid = true
      @access_token = response.parsed_response["access_token"]
    elsif response.code != 403
      raise OAuth::Unauthorized
    end
    valid
  end

  def request_access(*args)
    OpenStruct.new(token: @access_token, access_secret: nil)
  end

  def add(params)
    options = {
      body: {
        url: params["entry_url"],
        access_token: @access_token,
        consumer_key: ENV["POCKET_CONSUMER_KEY"],
      }.to_json,
      timeout: 10,
    }
    response = self.class.post(PATHS[:add], options)
    response.code
  rescue Net::OpenTimeout
    500
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_supported_sharing_service_url("pocket", host: ENV["PUSH_URL"])
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  def url_for(path)
    URI.join(self.class.base_uri, PATHS[path])
  end
end
