require "test_helper"

class ApiSubdomainRoutesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
  end

  test "serves an existing API route" do
    get "/v2/authentication"

    assert_response :unauthorized
  end

  test "does not serve browser routes" do
    get "/login"

    assert_response :not_found
  end

  test "does not serve operational routes" do
    get "/health_check"

    assert_response :not_found
  end

  test "redirects the API root to the normal host" do
    get "/"

    assert_redirected_to "http://example.com/"
    assert_response :found
  end

  test "returns not found for an unknown path" do
    get "/not-an-api-route"

    assert_response :not_found
  end

  test "preserves the legacy API response" do
    user = users(:ben)
    authorization = ActionController::HttpAuthentication::Basic.encode_credentials(user.email, default_password)

    get "/v1/anything", headers: {"Authorization" => authorization}

    assert_response :gone
  end

  test "keeps shared routes available on the normal host" do
    host! "www.example.com"

    get "/health_check"

    assert_response :ok
  end
end
