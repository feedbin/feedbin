require "test_helper"

class ApiV3AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = @user.oauth_applications.create!(name: "Test App", redirect_uri: "")
    @token = @application.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
  end

  test "rejects a request without credentials" do
    get "/v3/subscriptions"

    assert_response :unauthorized
    assert_equal "application/problem+json", response.media_type
    assert_equal %(Bearer realm="Feedbin"), response.headers["WWW-Authenticate"]

    body = JSON.parse(response.body)
    assert_equal "unauthorized", body["code"]
    assert_equal "https://api.feedbin.com/errors/unauthorized", body["type"]
    assert_equal 401, body["status"]
    assert_equal response.headers["X-Request-Id"], body["request_id"]
  end

  test "authenticates with a bearer token" do
    assert @token.plaintext_token.start_with?("fbn_v3_")

    get "/v3/subscriptions", headers: bearer(@token.plaintext_token)

    # No v3 endpoints exist yet, so an authenticated request reaches the
    # catch-all.
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["code"]
    assert_not_nil @token.reload.last_used_at
  end

  test "stores tokens hashed" do
    refute_equal @token.plaintext_token, @token.reload.token
  end

  test "rejects a revoked token" do
    plaintext = @token.plaintext_token
    @token.revoke

    get "/v3/subscriptions", headers: bearer(plaintext)

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], %(error="invalid_token")
  end

  test "rejects an unknown token" do
    get "/v3/subscriptions", headers: bearer("fbn_v3_not_a_real_token")

    assert_response :unauthorized
  end

  test "rejects HTTP Basic" do
    get "/v3/subscriptions", headers: {"Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(@user.email, default_password)}

    assert_response :unauthorized
    assert_equal %(Bearer realm="Feedbin"), response.headers["WWW-Authenticate"]
  end

  test "restricts accounts without the feature flag" do
    @user.setting_off!(:api_v3)

    get "/v3/subscriptions", headers: bearer(@token.plaintext_token)

    assert_response :forbidden
    assert_equal "restricted", JSON.parse(response.body)["code"]
  end

  test "restricts suspended accounts" do
    @user.update!(suspended: true)

    get "/v3/subscriptions", headers: bearer(@token.plaintext_token)

    assert_response :forbidden
  end

  test "requires a JSON body" do
    post "/v3/subscriptions", params: "url=example.com", headers: bearer(@token.plaintext_token, content_type: "application/x-www-form-urlencoded")

    assert_response :unsupported_media_type
    assert_equal "unsupported_media_type", JSON.parse(response.body)["code"]
  end

  test "rejects a body that is not JSON" do
    post "/v3/subscriptions", params: "{not json", headers: bearer(@token.plaintext_token, content_type: "application/json")

    assert_response :bad_request
    assert_equal "bad_request", JSON.parse(response.body)["code"]
  end

  test "accepts merge patch bodies on PATCH" do
    patch "/v3/subscriptions/1", params: {title: "New"}.to_json, headers: bearer(@token.plaintext_token, content_type: "application/merge-patch+json")

    assert_response :not_found
  end

  test "rejects merge patch bodies on POST" do
    post "/v3/subscriptions", params: {title: "New"}.to_json, headers: bearer(@token.plaintext_token, content_type: "application/merge-patch+json")

    assert_response :unsupported_media_type
  end

  test "serves the v3 root" do
    get "/v3", headers: bearer(@token.plaintext_token)

    assert_response :not_found
    assert_equal "application/problem+json", response.media_type
  end

  private

  def bearer(token, content_type: nil)
    {"Authorization" => "Bearer #{token}", "Content-Type" => content_type}.compact
  end
end
