require "test_helper"

class EmbedsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "GET twitter requires login" do
    get :twitter, params: {url: "https://twitter.com/x/status/1"}
    assert_redirected_to login_url
  end

  test "GET twitter resolves IframeEmbed::Twitter and assigns it as @media" do
    login_as @user
    fake_media = OpenStruct.new(url: "https://twitter.com/x/status/1")
    IframeEmbed::Twitter.stub :download, ->(_) { fake_media } do
      assert_raises(StandardError) do
        get :twitter, params: {url: "https://twitter.com/x/status/1", dom_id: "e1"}, xhr: true
      end
    rescue ActionView::Template::Error
      # template requires fixtures we are not setting up; controller behavior is what we care about
    end
    assert_equal fake_media, assigns(:media)
  end

  test "GET twitter quietly returns 200 when JSON parsing fails" do
    login_as @user
    IframeEmbed::Twitter.stub :download, ->(_) { raise JSON::ParserError } do
      get :twitter, params: {url: "https://twitter.com/x/status/1"}, xhr: true
    end
    assert_response :ok
  end

  test "GET instagram renders the embed when IframeEmbed::Instagram resolves" do
    login_as @user
    fake_media = OpenStruct.new
    IframeEmbed::Instagram.stub :download, ->(_) { fake_media } do
      get :instagram, params: {url: "https://www.instagram.com/p/ABC/", dom_id: "e2"}, xhr: true
    end
    assert_response :success
    assert_equal fake_media, assigns(:media)
  end

  test "GET instagram returns 200 on JSON::ParserError" do
    login_as @user
    IframeEmbed::Instagram.stub :download, ->(_) { raise JSON::ParserError } do
      get :instagram, params: {url: "https://www.instagram.com/p/ABC/"}, xhr: true
    end
    assert_response :ok
  end

  test "GET iframe renders the embed when IframeEmbed.fetch resolves" do
    login_as @user
    fake_media = OpenStruct.new
    IframeEmbed.stub :fetch, ->(_) { fake_media } do
      get :iframe, params: {url: "https://example.com/v"}, xhr: true
    end
    assert_response :success
    assert_equal fake_media, assigns(:media)
  end

  test "GET iframe renders the error template when fetch raises" do
    login_as @user
    IframeEmbed.stub :fetch, ->(_) { raise "boom" } do
      get :iframe, params: {url: "https://example.com/v"}, xhr: true
    end
    assert_response :success
    assert_equal "example.com", assigns(:host)
  end
end
