require 'test_helper'

class SubscriptionsControllerTest < ActionController::TestCase

  setup do
    @user = users(:ben)
  end

  test "should get index" do
    login_as @user
    get :index, format: :xml
    assert_response :success
  end

  test "should create subscription" do

  end

end