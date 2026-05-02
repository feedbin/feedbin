require "test_helper"

class InAppPurchasesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
  end

  test "show returns 404 when the purchase does not belong to the user" do
    login_as @user
    assert_raises(ActiveRecord::RecordNotFound) do
      get :show, params: {id: 999_999}
    end
  end
end
