require "test_helper"
class Api::V2::AuthenticationTokensControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
  end

  test "should create" do
    api_content_type
    login_as @user
    token = SecureRandom.hex

    post :create, params: {token: token}, format: :json

    assert_response :success
    assert_equal(token, @user.authentication_tokens.icloud.first.token)
  end
end
