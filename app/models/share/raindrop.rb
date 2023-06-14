class Share::Raindrop < Share::Service
  API_URL = "https://api.raindrop.io"

  # 1. raindrop = Raindrop.new
  # 2. redirect_to raindrop.authorize_redirect
  # 3. raindrop.request_access()
  # 4. save result database

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @client = OAuth2::AccessToken.from_hash consumer, JSON.load(@klass.oauth2_token)
    end
  end

  def consumer
    OAuth2::Client.new(ENV["RAINDROP_KEY"], ENV["RAINDROP_SECRET"], {
      site:          API_URL,
      token_url:     "/v1/oauth/access_token",
      authorize_url: "/v1/oauth/authorize",
      auth_scheme:   :request_body
    })
  end

  def add(params)
    entry = Entry.find(params[:entry_id])

    if @client.expired?
      @client = @client.refresh!
      @klass.update(oauth2_token: @client.to_hash.to_json)
    end

    response = HTTP
      .headers(@client.headers)
      .post(@client.client.connection.build_url("/rest/v1/raindrop"),
        json: {
          title: entry.title,
          link: entry.fully_qualified_url,
          pleaseParse: {},
          collectionId: -1
        })

    response.status.code
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  def authorize_redirect(params)
    consumer.auth_code.authorize_url(redirect_uri: redirect_uri)
  end

  def request_access(params)
    code = params[:code]
    access_token = consumer
      .auth_code
      .get_token(code,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code",
        headers: {
          "Content-Type" => "application/json"
        })
    {oauth2_token: access_token.to_hash.to_json}
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth2_response_supported_sharing_service_url("raindrop", host: ENV["PUSH_URL"])
  end
end
