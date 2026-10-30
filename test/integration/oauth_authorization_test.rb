require "test_helper"

class OauthAuthorizationTest < ActionDispatch::IntegrationTest
  REDIRECT_URI = "myreader://oauth/callback"

  setup do
    @owner = users(:ann)
    @application = @owner.oauth_applications.create!(name: "My Reader", redirect_uri: REDIRECT_URI)
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @verifier = SecureRandom.urlsafe_base64(48)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  test "exchanges an authorization code for a token with PKCE" do
    sign_in_as @user

    get oauth_authorization_path(authorize_params)
    assert_response :success
    assert_includes response.body, "Allow My Reader to use your Feedbin account?"

    post oauth_authorization_path, params: authorize_params
    assert_response :redirect
    location = URI(response.location)
    assert_equal "myreader", location.scheme
    code = Rack::Utils.parse_query(location.query)["code"]
    assert code.present?

    post oauth_token_path, params: token_params(code)
    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].start_with?("fbn_v3_")
    assert_nil body["expires_in"]
    assert_nil body["refresh_token"]

    host! "api.example.com"
    get "/v3/subscriptions", headers: {"Authorization" => "Bearer #{body["access_token"]}"}
    assert_response :not_found
  end

  test "rejects a code exchange with the wrong verifier" do
    sign_in_as @user
    post oauth_authorization_path, params: authorize_params
    code = Rack::Utils.parse_query(URI(response.location).query)["code"]

    post oauth_token_path, params: token_params(code, verifier: "wrong" * 10)

    assert_response :bad_request
  end

  test "requires PKCE" do
    sign_in_as @user

    get oauth_authorization_path(authorize_params.except(:code_challenge, :code_challenge_method))

    refute_includes response.body, "Allow My Reader"
  end

  test "sends a signed out user to the login form" do
    get oauth_authorization_path(authorize_params)

    assert_redirected_to login_url
  end

  test "a new user signs up and comes back to the authorization screen" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    get oauth_authorization_path(authorize_params)
    assert_redirected_to login_url

    post users_url, params: {user: {email: "new-reader@example.com", password: default_password, plan_id: plan.id}}

    assert_redirected_to oauth_authorization_url(authorize_params)
  ensure
    StripeMock.stop
  end

  test "is hidden from users without the feature flag" do
    @user.setting_off!(:api_v3)
    sign_in_as @user

    get oauth_authorization_path(authorize_params)

    assert_response :not_found
  end

  private

  def token_params(code, verifier: @verifier)
    {
      grant_type: "authorization_code",
      client_id: @application.uid,
      redirect_uri: REDIRECT_URI,
      code: code,
      code_verifier: verifier
    }
  end

  def authorize_params
    {
      client_id: @application.uid,
      redirect_uri: REDIRECT_URI,
      response_type: "code",
      state: "abc123",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }
  end
end
