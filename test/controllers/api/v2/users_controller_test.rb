require "test_helper"

class Api::V2::UsersControllerTest < ApiControllerTestCase
  test "should get index" do
    api_content_type
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    assert_difference "User.count", +1 do
      post :create, params: {user: {email: "example@example.com", password: default_password}}, format: :json
      assert_response :success
    end
    StripeMock.stop
  end

  test "should get info" do
    user = users(:ben)
    login_as user
    get :info, format: :json
    assert_has_keys keys, parse_json
  end

  private

  def keys
    %w[expires_at plan]
  end
end
