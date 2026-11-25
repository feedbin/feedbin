require "test_helper"

class OauthRegistrationTest < ActionDispatch::IntegrationTest
  REDIRECT_URI = "feedbin-next://oauth/callback"

  setup do
    # A new account is a new Stripe customer, on the trial plan.
    StripeMock.start
    Plan.all.each do |plan|
      create_stripe_plan(plan)
    rescue Stripe::InvalidRequestError
      # two fixtures share an id
    end
    owner = users(:ann)
    @application = owner.oauth_applications.create!(name: "Feedbin Next", redirect_uri: REDIRECT_URI, scopes: Api::V3::Scopes::FIRST_PARTY, confidential: false)
    @third_party = owner.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://oauth/callback")
    @verifier = SecureRandom.urlsafe_base64(48)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  teardown { StripeMock.stop }

  test "one of Feedbin's apps is shown the sign-up page, in the authorize page's dress" do
    get new_oauth_registration_path(authorize_params)

    assert_response :success
    assert_select "h1", text: "Create your Feedbin account"
    assert_includes response.body, "Free for #{Feedbin::Application.config.trial_days} days"
    assert_select "input[name=email]"
    assert_select "input[name=password][autocomplete=new-password]"
    assert_select "input[type=hidden][name=code_challenge][value=?]", @challenge
    assert_select "button", text: "Create Account"
    assert_select "a[href^=?]", oauth_authorization_path, text: "Sign In"
  end

  test "anyone else's app has no sign-up page" do
    get new_oauth_registration_path(authorize_params(@third_party))
    assert_response :not_found

    post oauth_registration_path, params: authorize_params(@third_party).merge(email: "newcomer@example.com", password: "secret passphrase")
    assert_response :not_found
    assert_nil User.find_by_email("newcomer@example.com")
  end

  test "creating an account signs it in, authorizes the app without asking, and ends in the app" do
    assert_difference "User.count", +1 do
      post oauth_registration_path, params: authorize_params.merge(email: "newcomer@example.com", password: "secret passphrase")
    end
    user = User.find_by_email!("newcomer@example.com")
    assert user.api_v3_enabled?
    assert_equal "trial", user.plan.stripe_id
    assert user.expires_at.future?
    assert_not user.suspended
    assert_response :redirect
    assert_equal oauth_authorization_path, URI(response.location).path
    assert_equal @challenge, Rack::Utils.parse_query(URI(response.location).query)["code_challenge"]

    # the page the sign-up redirects to answers the app at once
    follow_redirect!
    location = URI(response.location)
    assert_equal "feedbin-next", location.scheme
    query = Rack::Utils.parse_query(location.query)
    assert_equal "abc123", query["state"]

    post oauth_token_path, params: {grant_type: "authorization_code", client_id: @application.uid, redirect_uri: REDIRECT_URI, code: query["code"], code_verifier: @verifier}
    assert_response :success
    token = JSON.parse(response.body)
    assert_includes token["scope"], "account"

    host! "api.example.com"
    get "/v3/account", headers: {"Authorization" => "Bearer #{token["access_token"]}"}
    assert_response :success
    assert_equal "newcomer@example.com", JSON.parse(response.body)["email"]
  end

  test "the app is authorized without asking only that once" do
    post oauth_registration_path, params: authorize_params.merge(email: "newcomer@example.com", password: "secret passphrase")
    follow_redirect!
    assert_equal "feedbin-next", URI(response.location).scheme

    get oauth_authorization_path(authorize_params)
    assert_response :success
    assert_select "button", text: "Authorize"
  end

  test "an email already in use, or no password, makes no account and says why" do
    assert_no_difference "User.count" do
      post oauth_registration_path, params: authorize_params.merge(email: users(:ben).email, password: "secret passphrase")
    end
    assert_response :unprocessable_content
    assert_includes response.body, "Email has already been taken"
    assert_select "input[name=email][value=?]", users(:ben).email
    assert_select "input[type=hidden][name=state][value=abc123]"

    assert_no_difference "User.count" do
      post oauth_registration_path, params: authorize_params.merge(email: "newcomer@example.com", password: "")
    end
    assert_response :unprocessable_content
  end

  test "the authorize page of one of Feedbin's apps offers the sign-up page, and nobody else's does" do
    get oauth_authorization_path(authorize_params)
    assert_select "a[href^=?]", new_oauth_registration_path, text: "Create an account"

    get oauth_authorization_path(authorize_params(@third_party))
    assert_response :success
    assert_select "a", text: "Create an account", count: 0
  end

  private

  def authorize_params(application = @application)
    {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      state: "abc123",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }
  end
end
