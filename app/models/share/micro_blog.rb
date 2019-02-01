class Share::MicroBlog < Share::Service
  include HTTParty
  base_uri "https://micro.blog"
  debug_output

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @auth_token = @klass.api_token
    end
  end

  def add(params)
    body = {
      content: params["content"],
    }

    if params["name"].present?
      body[:name] = params["name"]
    end

    headers = {
      "Authorization" => "Bearer #{@auth_token}",
    }

    response = self.class.post("/micropub", body: body, headers: headers, timeout: 10)

    code = if response.code == 202
      200
    else
      500
    end

    code
  rescue Net::OpenTimeout
    500
  end

  def share(params)
    authenticated_share(@klass, params)
  end
end
