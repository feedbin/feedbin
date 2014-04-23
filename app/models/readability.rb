class Readability
  URL = "https://www.readability.com"

  def initialize(consumer_key = nil, consumer_secret = nil)
    if consumer_secret && consumer_secret
      consumer = OAuth::Consumer.new(ENV['READABILITY_READER_KEY'], ENV['READABILITY_READER_SECRET'], {site: URL})
      @client = OAuth::AccessToken.new(consumer, consumer_key, consumer_secret)
    end
  end

  def request_token(username, password)
    options = {
      site: URL,
      access_token_path: "/api/rest/v1/oauth/access_token/"
    }
    consumer = OAuth::Consumer.new(ENV['READABILITY_READER_KEY'], ENV['READABILITY_READER_SECRET'], options)
    consumer.get_access_token(nil, {}, { x_auth_username: username, x_auth_password: password, x_auth_mode: 'client_auth' })
  end

  def add(params)
    response = @client.post('/api/rest/v1/bookmarks', {url: params['entry_url']})
    code = response.code.to_i
    if [202, 409].include?(code)
      code = 200
    end
    code
  end

end