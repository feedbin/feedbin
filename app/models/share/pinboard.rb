class Share::Pinboard < Share::Service
  BASE_URL = "https://api.pinboard.in/v1"

  def initialize(klass = nil)
    @klass = klass
    if @klass.present?
      @auth_token = @klass.access_token
    end
  end

  def request_token(username, password)
    response = get("/user/api_token", auth_token: password, format: "json")
    if response.code != 200
      raise OAuth::Unauthorized.new(OpenStruct.new(code: response.code, message: "Unauthorized"))
    else
      OpenStruct.new(token: password, secret: "n/a")
    end
  end

  def add(params)
    defaults = {auth_token: @auth_token, format: "json"}
    options = params.slice(:toread, :shared, :tags, :extended, :description, :url)
    response = get("/posts/add", defaults.merge(options))
    if response.code == 200
      data = JSON.parse(response.to_s)
      if data["result_code"] == "done"
        200
      else
        500
      end
    else
      response.code
    end
  rescue HTTP::Error
    500
  end

  def share(params)
    authenticated_share(@klass, params)
  end

  private

  def get(path, params)
    HTTP.timeout(write: 5, connect: 5, read: 5)
      .get("#{BASE_URL}#{path}", params: params)
  end
end
