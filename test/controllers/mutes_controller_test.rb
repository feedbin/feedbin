require "test_helper"

class MutesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @mute = @user.actions.create!(
      query: "spam",
      all_feeds: true,
      action_type: Action.action_types[:mute],
      actions: ["mark_read"]
    )
  end

  test "GET index requires login" do
    get :index
    assert_redirected_to login_url
  end

  test "GET index lists the user's mutes" do
    login_as @user
    get :index, xhr: true
    assert_includes assigns(:mutes), @mute
  end

  test "POST create with button_action=save persists a mute" do
    login_as @user
    assert_difference -> { @user.actions.mute.count }, +1 do
      post :create, params: {query: "ad", all_feeds: "true", feed_id: @feed.id, button_action: "save"}, xhr: true
    end
  end

  test "POST create without button_action=save shows a preview without persisting" do
    login_as @user
    assert_no_difference -> { @user.actions.mute.count } do
      post :create, params: {query: "noise", feed_id: @feed.id}, xhr: true
    end
    assert assigns(:preview)
  end

  test "POST create flashes the validation error when save fails" do
    login_as @user
    # An empty query is invalid for a mute action
    post :create, params: {query: "", feed_id: @feed.id, button_action: "save"}, xhr: true
    refute_nil flash[:error]
  end

  test "DELETE destroy removes the mute and redirects for HTML" do
    login_as @user
    assert_difference -> { @user.actions.mute.count }, -1 do
      delete :destroy, params: {id: @mute.id}
    end
    assert_redirected_to actions_url
    assert_equal "Mute deleted.", flash[:notice]
  end

  test "DELETE destroy responds with JS that re-renders the list" do
    login_as @user
    delete :destroy, params: {id: @mute.id}, xhr: true
    assert_response :success
    refute_includes assigns(:mutes), @mute
  end
end
