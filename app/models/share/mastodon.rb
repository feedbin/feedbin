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
      @client = OAuth2::AccessToken.from_hash client(server.data["client_id"], server.data["client_secret"], server.host), JSON.parse(@klass.oauth2_token)
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
    response = HTTP.timeout(write: 5, connect: 5, read: 5)
      .headers(headers)
      .post(@client.client.connection.build_url("/api/v1/statuses"),
        json: params.slice(:status, :spoiler_text, :visibility),
        socket_class: Feedkit::PrivateAddressCheck::Socket)

    response.status.code
  rescue HTTP::Error, OpenSSL::SSL::SSLError, Feedkit::PrivateNetworkAddress
    :unreachable
  end

  def share(params)
    params[:idempotency_key] = SecureRandom.hex
    authenticated_share(@klass, params)
  end

  def authorize_redirect(params, state)
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
      }, socket_class: Feedkit::PrivateAddressCheck::Socket).parse

      server = OauthServer.create_with(data: data).find_or_create_by(host: uri.host)
    end

    client(server.data["client_id"], server.data["client_secret"], server.host)
      .auth_code
      .authorize_url(
        redirect_uri: redirect_uri(uri.host),
        grant_type: "authorization_code",
        scope: "write:statuses",
        response_type: "code",
        state: state
      )
  rescue HTTP::Error, OpenSSL::SSL::SSLError, Feedkit::PrivateNetworkAddress, Addressable::URI::InvalidURIError, JSON::ParserError
    raise AuthError.new("Invalid response from #{uri&.host || "Mastodon server"}.")
  end

  def request_access(params)
    code = params[:code]
    host = params[:mastodon_host]
    server = OauthServer.find_by_host!(host)
    oauth_client = client(server.data["client_id"], server.data["client_secret"], host)
    # A token exchange is one POST. Do not follow redirects with credentials.
    response = HTTP.timeout(connect: 5, write: 5, read: 5).post(oauth_client.token_url,
      socket_class: Feedkit::PrivateAddressCheck::Socket,
      form: {
        client_id: oauth_client.id,
        client_secret: oauth_client.secret,
        code: code,
        redirect_uri: redirect_uri(host),
        grant_type: "authorization_code",
        scope: "write:statuses"
      })
    raise AuthError, "Invalid response from the Mastodon server." unless response.status.success?

    data = JSON.parse(response.to_s)
    unless data.is_a?(Hash) && data["access_token"].is_a?(String) && data["access_token"].present?
      raise AuthError, "Invalid response from the Mastodon server."
    end

    access_token = OAuth2::AccessToken.from_hash(oauth_client, data)
    {oauth2_token: access_token.to_hash.to_json, mastodon_host: server.host}
  rescue HTTP::Error, OpenSSL::SSL::SSLError, Feedkit::PrivateNetworkAddress, JSON::ParserError
    raise AuthError.new("Could not connect to the Mastodon server.")
  end

  def redirect_uri(host)
    Rails.application.routes.url_helpers.oauth2_response_supported_sharing_service_url("mastodon", host: ENV["PUSH_URL"], mastodon_host: host)
  end
end
