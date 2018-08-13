class Share::Readability < Share::Service
  URL = "https://www.readability.com"

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @client = OAuth::AccessToken.new(consumer, @klass.access_token, @klass.access_secret)
    end
  end

  def request_token(username, password)
    consumer.get_access_token(nil, {}, {x_auth_username: username, x_auth_password: password, x_auth_mode: "client_auth"})
  end

  def consumer
    options = {
      site: URL,
      access_token_path: "/api/rest/v1/oauth/access_token/",
    }
    OAuth::Consumer.new(ENV["READABILITY_READER_KEY"], ENV["READABILITY_READER_SECRET"], options)
  end

  def add(params)
    response = @client.post("/api/rest/v1/bookmarks", {url: params["entry_url"]})
    code = response.code.to_i
    if [202, 409].include?(code)
      code = 200
    end
    code
  end

  def share(params)
    authenticated_share(@klass, params)
  end
end
