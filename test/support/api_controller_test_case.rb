class ApiControllerTestCase < ActionController::TestCase
  include Feedbin::Assertions
  setup do
    @request.headers["HTTP_HOST"] = "api.#{@request.headers["HTTP_HOST"]}"
  end

  def api_content_type
    @request.headers["Content-Type"] = "application/json; charset=utf-8"
  end
end
