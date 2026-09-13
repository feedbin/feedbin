require "test_helper"

class Api::V2::IconsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
  end

  test "serves the images row's unified url for each subscribed host" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      rows = @feeds.map { create_favicon_row(it.host) }
      login_as @user

      get :index, format: :json

      assert_response :success
      expected = @feeds.zip(rows).map { |feed, row|
        {"host" => feed.host, "url" => "https://images.example.com/#{row.storage_path}"}
      }
      assert_equal expected.sort_by { it["host"] }, parse_json.sort_by { it["host"] }
    end
  end

  test "omits a host with no images row" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      first, second = @feeds
      row = create_favicon_row(first.host)
      login_as @user

      get :index, format: :json

      icons = parse_json.index_by { it["host"] }
      assert_equal "https://images.example.com/#{row.storage_path}", icons.fetch(first.host)["url"]
      assert_nil icons[second.host]
    end
  end
end
