class Share::MicroBlog < Share::Service
  BASE_URL = "https://micro.blog"

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @auth_token = @klass.api_token || @klass.access_token
    end
  end

  def request_token(username, password)
    response = client.post("#{BASE_URL}/account/verify", params: {token: password})
    if parse(response)["token"]
      OpenStruct.new(token: password, secret: "n/a")
    else
      raise OAuth::Unauthorized.new(OpenStruct.new(code: response.code, message: "Unauthorized"))
    end
  end

  def add(params)
    body = {
      content: params["content"]
    }

    if params["name"].present?
      body[:name] = params["name"]
    end

    response = client
      .auth("Bearer #{@auth_token}")
      .post("#{BASE_URL}/micropub", form: body)

    code = if response.code == 202
      200
    else
      500
    end

    code
  rescue HTTP::Error
    500
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  private

  def client
    HTTP.timeout(write: 5, connect: 5, read: 5)
  end

  def parse(response)
    JSON.parse(response.to_s)
  rescue JSON::ParserError
    {}
  end
end
