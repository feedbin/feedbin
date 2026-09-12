require "test_helper"

class Api::V2::FaviconsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
  end

  # Retired with the base64 column: the route answers, the body is empty.
  test "index is an empty array" do
    login_as @user
    @feeds.each { Favicon.create!(host: it.host, url: "http://example.com/#{it.host}.png") }

    get :index, format: :json

    assert_response :success
    assert_equal [], parse_json
  end
end
