class Pinboard
  include HTTParty
  base_uri 'https://api.pinboard.in/v1'

  def initialize(auth_token = nil)
    @auth_token = auth_token
  end

  def request_token(username, password)
    response = self.class.get('/user/api_token', basic_auth: {username: username, password: password}, query: {format: 'json'})
    if response.code == 401
      raise OAuth::Unauthorized
    else
      response = JSON.load(response.body)
      OpenStruct.new(token: "#{username}:#{response['result']}", secret: 'n/a')
    end
  end

  def add(params)
    defaults = {auth_token: @auth_token, format: 'json'}
    options = params.slice(:toread, :shared, :tags, :extended, :description, :url)
    response = self.class.get('/posts/add', query: defaults.merge(options))
    if response.code == 200
      data = JSON.load(response.body)
      if data['result_code'] == "done"
        code = 200
      else
        code = 500
      end
    else
      response.code
    end
  end
end