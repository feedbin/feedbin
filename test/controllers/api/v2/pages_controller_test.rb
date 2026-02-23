require "test_helper"

class Api::V2::PagesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
  end

  test "should create page" do
    login_as @user
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    assert_difference "Entry.count", +1 do
      post :create, params: {url: "http://example.com"}, format: :json
      assert_response :created
    end
  end

  test "should enqueue retry" do
    login_as @user
    stub_request(:get, /extract\.example\.com/).to_return(status: 500)
    url = "http://example.com/saved_page"
    Sidekiq::Worker.clear_all
    assert_difference -> {SavePage.jobs.size}, +1 do
      post :create, params: {url: "http://example.com"}, format: :json
      assert_response :created
    end
  end


  test "should destroy page" do
    login_as @user
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    post :create, params: {url: "http://example.com"}, format: :json

    result = JSON.load(response.body)

    assert_difference -> { Entry.count }, -1 do
      delete :destroy, params: { id: result["id"] }
    end
  end
end
