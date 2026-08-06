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

  test "renders an empty conversation when micro.blog is unreachable" do
    login_as @user
    entry = @entries.first
    stub_request(:get, "https://micro.blog/posts/conversation?id=#{entry.entry_id}").to_timeout

    get :thread, params: {id: entry.id}, xhr: true

    assert_response :success
    assert_equal [], assigns(:microposts)
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

  # The http gem defaults to no deadline at all, so a micro.blog that accepts
  # the connection and then stops talking holds a Puma thread for as long as
  # the socket stays open. Every other outbound call in the app sets one.
  test "the micro.blog conversation request carries a timeout" do
    login_as @user
    entry = @entries.first
    url = "https://micro.blog/posts/conversation?id=#{entry.entry_id}"
    stub_request_file("microblog_conversation_response.json", url, headers: {"Content-Type" => "application/json; charset=utf-8"})

    client = nil
    HTTP.stub(:timeout, ->(**options) { client = options; HTTP }) do
      get :thread, params: {id: entry.id}, xhr: true
    end

    assert client, "the request was built without HTTP.timeout"
    assert client[:read], "no read deadline"
    assert client[:connect], "no connect deadline"
  end

  # Item-level authors are optional in JSON Feed, and Micropost#valid? already
  # knows a post with no author profile cannot be rendered -- Entry#micropost
  # honours it. Building them here without asking turned one authorless reply
  # into a 500 for the whole dialog.
  test "should get thread when a reply carries no author" do
    login_as @user

    entry = @entries.first
    body = JSON.parse(File.read(support_file("microblog_conversation_response.json")))
    body["items"] = [body["items"].first.except("author")]

    url = "https://micro.blog/posts/conversation?id=#{entry.entry_id}"
    stub_request(:get, url).to_return(
      status: 200,
      body: body.to_json,
      headers: {"Content-Type" => "application/json; charset=utf-8"}
    )

    get :thread, params: {id: entry.id}, xhr: true

    assert_response :success
    assert_empty assigns(:microposts)
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
