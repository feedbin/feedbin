class Share::Instapaper < Share::Service
  URL = "https://www.instapaper.com"

  def initialize(klass = nil)
    @klass = klass
    if @klass.present? && @klass.access_token.present? && @klass.access_secret.present?
      @client = OAuth::AccessToken.new(consumer, @klass.access_token, @klass.access_secret)
    end
  end

  def request_token(username, password)
    consumer.get_access_token(nil, {}, {x_auth_username: username, x_auth_password: password, x_auth_mode: "client_auth"})
  end

  def consumer
    options = {
      site: URL,
      access_token_path: "/api/1/oauth/access_token",
    }
    OAuth::Consumer.new(ENV["INSTAPAPER_KEY"], ENV["INSTAPAPER_SECRET"], options)
  end

  def add(params)
    response = @client.post("/api/1/bookmarks/add", {url: params["entry_url"]})
    code = response.code.to_i
    if code == 201
      code = 200
    end
    code
  end

  def share(params)
    authenticated_share(@klass, params)
  end
end
