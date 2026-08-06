require "test_helper"

class MicropostsControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get thread" do
    login_as @user

    entry = @entries.first

    html_url = "https://micro.blog/posts/conversation?id=#{entry.entry_id}"
    stub_request_file("microblog_conversation_response.json", html_url, headers: {"Content-Type" => "application/json; charset=utf-8"})

    get :thread, params: {id: entry.id}, xhr: true

    assert assigns(:microposts)
    assert_response :success
  end

  test "should not get thread for an entry the user cannot read" do
    entry = create_entry(feeds(:kottke))
    refute @user.can_read_entry?(entry.id), "precondition: user cannot read this entry"

    login_as @user

    # No micro.blog stub: WebMock fails the test if the action makes the
    # outbound request anyway.
    get :thread, params: {id: entry.id}, xhr: true

    assert_response :not_found
    assert_nil assigns(:microposts)
  end
end
