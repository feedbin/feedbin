class Share::Pocket < Share::Service
  BASE_URL = "https://getpocket.com"

  PATHS = {
    auth_authorize: "/auth/authorize",
    oauth_request: "/v3/oauth/request",
    oauth_authorize: "/v3/oauth/authorize",
    add: "/v3/add"
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
    response = post(:oauth_request, consumer_key: ENV["POCKET_CONSUMER_KEY"], redirect_uri: redirect_uri)
    if response.code == 200
      code = parse(response)["code"]
      OpenStruct.new(token: code, secret: code, authorize_url: authorize_url(code))
    end
  end

  def authorize(code)
    post(:oauth_authorize, consumer_key: ENV["POCKET_CONSUMER_KEY"], code: code)
  end

  def response_valid?(session, params)
    response = authorize(session[:oauth_token])
    valid = false
    if response.code == 200
      valid = true
      @access_token = parse(response)["access_token"]
    elsif response.code != 403
      ErrorService.notify(
        error_class: "Share::Pocket#response_valid?",
        error_message: "response invalid",
        parameters: {
          code: response.code,
          body: response.to_s,
          headers: response.headers.to_h
        }
      )
      raise OAuth::Unauthorized
    end
    valid
  end

  def request_access(*args)
    OpenStruct.new(token: @access_token, access_secret: nil)
  end

  def add(params)
    response = post(:add,
      url: params["entry_url"],
      access_token: @access_token,
      consumer_key: ENV["POCKET_CONSUMER_KEY"])
    response.code
  rescue HTTP::Error
    500
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_supported_sharing_service_url("pocket", host: ENV["PUSH_URL"])
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  def url_for(path)
    URI.join(BASE_URL, PATHS[path])
  end

  private

  def post(path, body)
    HTTP.timeout(write: 5, connect: 5, read: 5)
      .headers("Content-Type" => "application/json; charset=UTF-8", "X-Accept" => "application/json")
      .post(url_for(path), body: body.to_json)
  end

  # Pocket answers with JSON when asked for it, but the parse should not
  # depend on the server sending a matching content type.
  def parse(response)
    JSON.parse(response.to_s)
  rescue JSON::ParserError
    {}
  end
end
