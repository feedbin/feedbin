require "test_helper"

class ActionsControllerTest < ActionController::TestCase
  setup do
    @action = actions(:ben_one)
  end

  test "should get index" do
    login_as users(:ben)
    get :index
    assert_response :success
    assert_not_nil assigns(:actions)
  end

  test "should get new" do
    login_as users(:ben)
    get :new
    assert_response :success
  end

  test "should create action" do
    login_as users(:ben)

    feed = feeds(:daring_fireball)

    params = {
      title: "Star",
      query: "john",
      all_feeds: 0,
      feed_ids: [feed.id],
      actions: ["star"],
    }

    assert_difference("Action.count") do
      post :create, params: {action_params: params}, xhr: true
    end
  end

  test "should get edit" do
    login_as users(:ben)
    get :edit, params: {id: @action}
    assert_response :success
  end

  test "should update action" do
    new_title = "New"

    login_as users(:ben)

    patch :update, params: {id: @action, action_params: {title: new_title}}, xhr: true

    @action.reload
    assert_equal new_title, @action.title
  end

  test "should destroy action" do
    login_as users(:ben)
    assert_difference("Action.count", -1) do
      delete :destroy, params: {id: @action}
    end

    assert_redirected_to actions_path
  end
end
