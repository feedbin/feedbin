require "test_helper"

class OauthDevelopmentTokenTest < ActionDispatch::IntegrationTest
  setup { @user = users(:ben) }

  test "mints a token that authenticates v3" do
    post "/oauth/development_token", params: {user_id: @user.id}
    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].start_with?("fbn_v3_")
    assert_equal "Bearer", body["token_type"]
    assert_equal "read write account", body["scope"]
    assert_kind_of Integer, body["created_at"]
    assert @user.reload.api_v3_enabled?

    host! "api.example.com"
    get "/v3/subscriptions", headers: {"Authorization" => "Bearer #{body["access_token"]}"}
    assert_response :success
  end

  test "each call mints a new token and both work" do
    2.times { post "/oauth/development_token", params: {user_id: @user.id} }
    assert_equal 2, Doorkeeper::Application.find_by(uid: Api::V3::DevelopmentApplication::CLIENT_ID).access_tokens.count
  end

  test "unknown user is not found" do
    post "/oauth/development_token", params: {user_id: 0}
    assert_response :not_found
    assert_empty response.body
  end

  test "ensure! finds the application it created" do
    application = Api::V3::DevelopmentApplication.ensure!(owner: @user)

    assert_equal application, Api::V3::DevelopmentApplication.ensure!(owner: users(:ann))
    assert_equal "Feedbin Next (development)", application.name
    assert_equal Api::V3::DevelopmentApplication::REDIRECT_URI, application.redirect_uri
    assert_not application.confidential?
  end
end
