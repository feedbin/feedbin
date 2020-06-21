require "test_helper"

class PagesInternalControllerTest < ActionController::TestCase
  test "creates a new job to find page" do
    user = users(:ben)
    login_as user

    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})

    assert_difference "Entry.count", +1 do
      post :create, params: {url: "http://example.com/article"}, xhr: true
    end
    assert_response :success
  end
end
