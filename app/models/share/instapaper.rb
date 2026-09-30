class Share::Instapaper < Share::Service
  URL = "https://www.instapaper.com"

  # 1. instapaper = Instapaper.new
  # 2. redirect_to instapaper.authorize_redirect(params, state)
  # 3. instapaper.request_access(params)
  # 4. save result to the database
  #
  # Access tokens do not expire and there is no refresh token, so the bearer
  # token is stored as a plain string in access_token. Tokens issued through
  # the old xAuth flow are valid bearer tokens too, so no migration is needed.

  def initialize(klass = nil)
    @klass = klass
  end

  def consumer
    OAuth2::Client.new(ENV["INSTAPAPER_KEY"], ENV["INSTAPAPER_SECRET"], {
      site:          URL,
      authorize_url: "/oauth2/authorize",
      token_url:     "/oauth2/token",
      auth_scheme:   :request_body
    })
  end

  def authorize_redirect(params, state)
    consumer.auth_code.authorize_url(redirect_uri: redirect_uri, state: state)
  end

  def request_access(params)
    access_token = consumer.auth_code.get_token(params[:code], redirect_uri: redirect_uri)
    {access_token: access_token.token}
  end

  def add(params)
    entry = Entry.find(params[:entry_id])
    response = HTTP
      .timeout(write: 5, connect: 5, read: 10)
      .auth("Bearer #{@klass.access_token}")
      .post("#{URL}/api/2/bookmarks", json: {url: params["entry_url"], title: entry.title}.compact_blank)

    response.status.success? ? 200 : response.status.code
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth2_response_supported_sharing_service_url("instapaper", host: ENV["PUSH_URL"])
  end
end
