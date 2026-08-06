require "test_helper"
require "base64"

class Api::V2::AuthenticationControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should authenticate" do
    login_as @user
    get :index
    assert_response :success
  end

  test "should not authenticate" do
    get :index
    assert_response :unauthorized
  end

  test "should not authenticate a username that is not valid UTF-8" do
    # \xC3\x28 is a two-byte lead followed by a byte that cannot continue it.
    # Postgres rejects it at the protocol level, before the query runs.
    credentials = "\xC3\x28admin@example.com:password".b
    @request.headers[:authorization] = "Basic " + Base64.strict_encode64(credentials)

    get :index

    assert_response :unauthorized
  end
end
