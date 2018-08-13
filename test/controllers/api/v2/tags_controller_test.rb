require "test_helper"

class Api::V2::TagsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @tagging = @user.feeds.first.tag("new tag", @user, false).first
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    results = parse_json
    assert_has_keys keys, results.first
  end

  private

  def keys
    %w[id name]
  end
end
