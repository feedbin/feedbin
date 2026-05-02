require "test_helper"

class BillingEventsControllerTest < ActionController::TestCase
  test "GET show requires login" do
    get :show, params: {id: 1}
    assert_redirected_to login_url
  end
end
