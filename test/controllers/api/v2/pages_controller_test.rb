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
end
