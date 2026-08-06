require "test_helper"

class SiteControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get index" do
    login_as @user
    get :index
    assert_response :success
  end

  test "should get headers" do
    login_as @user
    get :index
    assert_response :success
  end

  test "manifest declares a POST share target" do
    login_as @user
    get :manifest, params: {theme: "day", format: :json}
    assert_response :success

    share_target = JSON.parse(@response.body)["share_target"]
    # Web Share Target defaults to GET, and /pages no longer routes GET — the
    # share target only works if the manifest says POST outright.
    assert_equal "POST", share_target["method"]
    assert_equal "application/x-www-form-urlencoded", share_target["enctype"]
  end
end
