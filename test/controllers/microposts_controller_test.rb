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

  test "should get thread when a reply carries no date_published" do
    login_as @user

    entry = @entries.first
    body = JSON.parse(File.read(support_file("microblog_conversation_response.json")))
    # date_published is optional in JSON Feed, both v1 and v1.1.
    body["items"] = [body["items"].first.except("date_published")]

    html_url = "https://micro.blog/posts/conversation?id=#{entry.entry_id}"
    stub_request(:get, html_url).to_return(
      status: 200,
      body: body.to_json,
      headers: {"Content-Type" => "application/json; charset=utf-8"}
    )

    get :thread, params: {id: entry.id}, xhr: true

    assert_response :success
    assert_equal 1, assigns(:microposts).length
    assert_nil assigns(:microposts).first.published
  end
end
