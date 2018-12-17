require "test_helper"

class ErrorsControllerTest < ActionController::TestCase
  test "not found" do
    get :not_found
    assert_response :not_found
  end
end
