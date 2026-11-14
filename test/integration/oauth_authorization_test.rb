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
    assert_includes response.body, "My Reader is requesting access to your account"

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

    refute_includes response.body, "My Reader is requesting access"
  end

  test "a signed out visitor sees the authorize page without a redirect or notice" do
    get oauth_authorization_path(authorize_params)

    assert_response :success
    assert_select "input[name=email]"
    assert_select "input[name=password]"
    assert_select "button", text: "Authorize"
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

  test "the authorize page says who is asking and as whom" do
    sign_in_as @user

    get oauth_authorization_path(authorize_params)

    assert_select "h1", text: "My Reader is requesting access to your account"
    assert_includes response.body, @user.email
  end

  test "cancelling does not send the next sign in back to the authorize page" do
    get oauth_authorization_path(authorize_params)
    delete oauth_authorization_path, params: authorize_params

    sign_in_as @user

    assert_redirected_to root_url
  end

  test "authorizing does not leave a return location behind" do
    get oauth_authorization_path(authorize_params)
    post oauth_authorization_path, params: authorize_params.merge(email: @user.email, password: default_password)

    sign_in_as @user

    assert_redirected_to root_url
  end

  test "shows the application's logo above the title" do
    Api::V3::ApplicationProfile.for(@application).update!(logo_file: Rack::Test::UploadedFile.new(support_file("image.png"), "image/png"))

    get oauth_authorization_path(authorize_params)
    assert_select "img[alt=?]", "My Reader"

    get css_select("img[alt='My Reader']").first["src"]
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal :png, ImageFormat.new(response.body).format
  end

  test "an application without a logo shows none" do
    get oauth_authorization_path(authorize_params)
    assert_select "img", count: 0

    get oauth_application_logo_path(@application.uid)
    assert_response :not_found
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
