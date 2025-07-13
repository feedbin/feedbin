require "test_helper"

class Extension::V1::PagesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @request.headers["Content-Type"] = "application/json"
  end

  test "creates page with page token" do
    Sidekiq::Worker.clear_all
    assert_difference "SavePageFromExtension.jobs.size", +1 do
      post :create, params: {
        url: "http://example.com/article",
        title: "Example Article",
        content: "<html><body>Article content</body></html>",
        page_token: @user.page_token
      }, format: :json
      assert_response :success
    end
  end

  test "requires authentication" do
    post :create, params: {
      url: "http://example.com/article",
      title: "Example Article",
      content: "<html><body>Article content</body></html>"
    }, format: :json
    assert_response :unauthorized
  end

  test "writes content to temporary file" do
    content = "<html><body>Test content</body></html>"

    SavePageFromExtension.stub :perform_async, ->(user_id, url, title, path) {
      assert_equal @user.id, user_id
      assert_equal "http://example.com/article", url
      assert_equal "Test Article", title
      assert File.exist?(path)
      assert_equal content, File.read(path)
      true
    } do
      post :create, params: {
        url: "http://example.com/article",
        title: "Test Article",
        content: content,
        page_token: @user.page_token
      }, format: :json
    end
  end

  test "sets CORS headers" do
    post :create, params: {
      url: "http://example.com/article",
      email: @user.email,
      password: default_password
    }, format: :json
    assert_equal "*", @response.headers["Access-Control-Allow-Origin"]
    assert_equal "POST, OPTIONS", @response.headers["Access-Control-Allow-Methods"]
  end
end