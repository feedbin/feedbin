class ApiControllerTestCase < ActionController::TestCase
  include Feedbin::Assertions
  setup do
    @request.headers["HTTP_HOST"] = "api.#{@request.headers["HTTP_HOST"]}"
  end
end