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
    assert_includes response.body, "Authorize My Reader to use your Feedbin account"

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
    assert_response :success
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

    refute_includes response.body, "Authorize My Reader"
  end

  test "a signed out visitor sees the authorize page without a redirect or notice" do
    get oauth_authorization_path(authorize_params)

    assert_response :success
    assert_select "input[name=email]"
    assert_select "input[name=password]"
    assert_select "button", text: "Sign in and authorize"
    refute_includes response.body, "Please sign in."
  end

  test "signing in on the authorize page authorizes and signs in to Feedbin" do
    post oauth_authorization_path, params: authorize_params.merge(email: @user.email, password: default_password)

    location = URI(response.location)
    assert_equal "myreader", location.scheme
    assert Rack::Utils.parse_query(location.query)["code"].present?

    get oauth_authorization_path(authorize_params)
    assert_select "input[name=password]", count: 0
    assert_select "button", text: "Authorize"
  end

  test "a wrong password returns to the authorize page with every parameter kept" do
    state = "a b&c=d"
    post oauth_authorization_path, params: authorize_params.merge(state: state, email: @user.email, password: "nope")

    follow_redirect!
    assert_equal oauth_authorization_path, path
    assert_includes response.body, "Invalid email or password"
    assert_select "input[name=email][value=?]", @user.email
    assert_select "input[name=state][value=?]", state
    assert_equal 0, Doorkeeper::AccessGrant.count
  end

  test "an unknown email or blank password is refused the same way" do
    [{email: "nobody@example.com", password: default_password}, {email: @user.email, password: ""}].each do |credentials|
      post oauth_authorization_path, params: authorize_params.merge(credentials)
      follow_redirect!
      assert_includes response.body, "Invalid email or password"
    end
  end

  test "an account without API v3 is not signed in" do
    post oauth_authorization_path, params: authorize_params.merge(email: users(:ann).email, password: default_password)

    follow_redirect!
    assert_includes response.body, "This account can’t connect apps yet"
    assert_select "input[name=password]"
  end

  test "a signed out visitor can cancel" do
    delete oauth_authorization_path, params: authorize_params

    query = Rack::Utils.parse_query(URI(response.location).query)
    assert_equal "access_denied", query["error"]
    assert_equal "abc123", query["state"]
  end

  test "an unregistered redirect URI shows the error page to a signed out visitor" do
    get oauth_authorization_path(authorize_params.merge(redirect_uri: "https://evil.example/cb"))

    assert_includes response.body, "This app can’t connect to Feedbin"
    assert_select "input[name=password]", count: 0
  end

  test "not you signs out and returns to the authorize page" do
    sign_in_as @user

    delete oauth_session_path, params: authorize_params

    follow_redirect!
    assert_equal oauth_authorization_path, path
    assert_select "input[name=password]"
    assert_select "input[name=state][value=?]", "abc123"
  end

  test "not you never redirects off site" do
    sign_in_as @user

    delete oauth_session_path, params: authorize_params.merge(redirect_uri: "https://evil.example/cb")

    assert_equal "www.example.com", URI(response.location).host
    follow_redirect!
    assert_includes response.body, "This app can’t connect to Feedbin"
  end

  test "a signed in visitor is offered a way to switch accounts" do
    sign_in_as @user

    get oauth_authorization_path(authorize_params)

    assert_select "form#oauth_switch_account[action=?]", oauth_session_path
    assert_select "button[form=oauth_switch_account]", text: "Not you?"
  end

  test "the authorize page says what is granted, to whom, and how to undo it" do
    sign_in_as @user

    get oauth_authorization_path(authorize_params)

    assert_select "h1", text: "Authorize My Reader to use your Feedbin account"
    assert_includes response.body, "read and change your subscriptions, articles and settings"
    assert_includes response.body, @user.email
    assert_includes response.body, "returned to My Reader"
    assert_includes response.body, "revoke access any time in Settings"
  end

  test "a web redirect names the host the visitor returns to" do
    @application.update!(redirect_uri: "https://reader.example/callback")
    sign_in_as @user

    get oauth_authorization_path(authorize_params.merge(redirect_uri: "https://reader.example/callback"))

    assert_includes response.body, "returned to My Reader (reader.example)"
  end

  test "a new user signs up and comes back to the authorization screen" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    get oauth_authorization_path(authorize_params)

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
