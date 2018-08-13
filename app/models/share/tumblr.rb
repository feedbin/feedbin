class Share::Tumblr < Share::Service
  URL = "http://www.tumblr.com"
  API_URL = "https://api.tumblr.com/v2"

  # 1. tumblr = Tumblr.new
  # 2. client = tumblr.request_token
  # 3. session[:tumblr_token] = client.token; session[:tumblr_secret] = client.secret
  # 4. redirect_to client.authorize_url
  # 5. tumblr = Tumblr.new
  # 6. access_token = tumblr.request_access(session[:tumblr_token], session[:tumblr_secret], params[:oauth_verifier])
  # 7. save access_token.token and access_token.secret in the database

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @client = OAuth::AccessToken.new(consumer, @klass.access_token, @klass.access_secret)
    end
  end

  def consumer
    options = {
      site: URL,
      request_token_path: "/oauth/request_token",
      authorize_path: "/oauth/authorize",
      access_token_path: "/oauth/access_token",
      http_method: :post,
    }
    OAuth::Consumer.new(ENV["TUMBLR_KEY"], ENV["TUMBLR_SECRET"], options)
  end

  def request_token
    consumer.get_request_token(oauth_callback: redirect_uri)
  end

  def request_access(oauth_token, oauth_token_secret, oauth_verifier)
    params = {oauth_token: oauth_token, oauth_token_secret: oauth_token_secret}
    client = OAuth::RequestToken.from_hash(consumer, params)
    client.get_access_token(oauth_verifier: oauth_verifier)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_supported_sharing_service_url("tumblr", host: ENV["PUSH_URL"])
  end

  def response_valid?(session, params)
    params[:oauth_verifier].present?
  end

  def user_info
    result = @client.get("#{API_URL}/user/info")
    JSON.load(result.body)
  end

  def add(params)
    @klass.update(default_option: params[:site])
    options = {
      format: params["format"],
      state: params["state"],
    }

    if params[:type] == "quote"
      options[:type] = "quote"
      options[:source] = params["source"]
      options[:quote] = params["description"]
    else
      options[:type] = "link"
      options[:url] = params["entry_url"]
      options[:title] = params["title"]
      options[:description] = params["description"]
    end

    if params["tags"].present?
      options[:tags] = params["tags"]
    end
    response = @client.post("#{API_URL}/blog/#{params[:site]}/post", options)
    code = response.code.to_i
    if code == 201
      code = 200
    end
    code
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  def after_activate
    get_blogs
  end

  def get_blogs
    info = user_info
    if info["response"].present?
      tumblr_hosts = info["response"]["user"]["blogs"].collect { |blog| URI.parse(blog["url"]).host }
    end
  end
end
