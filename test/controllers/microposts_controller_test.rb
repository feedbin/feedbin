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
end
