require "test_helper"

class Api::V2::FaviconsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @favicons = @feeds.map { |feed|
      Favicon.create!(host: feed.host, url: feed.host)
    }
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    favicons = parse_json
    assert_equal(@favicons.length, favicons.length)
  end
end
