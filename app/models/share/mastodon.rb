class Share::Mastodon < Share::Service
  # 1. mastodon = Mastodon.new
  # 2. find or create app on server host
  # 3. redirect to authorize url, set session[:mastodon_server]
  # 4. request token, find server from session[:mastodon_server]
  # 5. save bearer token and server

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      server = OauthServer.find_by_host!(@klass.mastodon_host)
      @client = OAuth2::AccessToken.from_hash client(server.data["client_id"], server.data["client_secret"], server.host), JSON.load(@klass.oauth2_token)
    end
  end

  def client(id, secret, host)
    OAuth2::Client.new(id, secret, {
      site: URI::HTTPS.build(host: host),
      auth_scheme: :request_body
    })
  end

  def add(params)
    headers = @client.headers.merge({"Idempotency-Key" => params[:idempotency_key]})
    response = HTTP
      .headers(headers)
      .post(@client.client.connection.build_url("/api/v1/statuses"),
        json: params.slice(:status, :spoiler_text, :visibility)
      )

    response.status.code
  end

  def share(params)
    params[:idempotency_key] = SecureRandom.hex
    authenticated_share(@klass, params)
  end

  def authorize_redirect(params)
    host = params[:mastodon_url]
    uri = Addressable::URI.heuristic_parse(host)

    if uri.nil? || uri.host.nil?
      raise AuthError.new(message: "Invalid Mastodon server.")
    end

    uri.scheme = "https"
    uri.path = "/api/v1/apps"

    server = OauthServer.find_by_host(uri.host)

    if server.nil?
      data = HTTP.timeout(write: 2, connect: 2, read: 2).post(uri, json: {
      	client_name: "Feedbin",
      	redirect_uris: redirect_uri(uri.host),
      	scopes: "write:statuses",
      	website: ENV["PUSH_URL"]
      }).parse

      server = OauthServer.create_with(data: data).find_or_create_by(host: uri.host)
    end

    client(server.data["client_id"], server.data["client_secret"], server.host)
      .auth_code
      .authorize_url(
        redirect_uri: redirect_uri(uri.host),
        grant_type: "authorization_code",
        scope: "write:statuses",
        response_type: "code"
      )
  rescue HTTP::Error => exception
    ErrorService.notify(exception)
    raise AuthError.new("Invalid response from #{uri.host}.")
  end

  def request_access(params)
    code = params[:code]
    host = params[:mastodon_host]
    server = OauthServer.find_by_host!(host)
    access_token = client(server.data["client_id"], server.data["client_secret"], host)
      .auth_code
      .get_token(code,
        redirect_uri: redirect_uri(host),
        grant_type: "authorization_code",
        scope: "write:statuses"
      )
    {oauth2_token: access_token.to_hash.to_json, mastodon_host: server.host}
  end

  def redirect_uri(host)
    Rails.application.routes.url_helpers.oauth2_response_supported_sharing_service_url("mastodon", host: ENV["PUSH_URL"], mastodon_host: host)
  end
end
