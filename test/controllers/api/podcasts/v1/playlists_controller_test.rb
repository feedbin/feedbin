require "test_helper"
class Api::Podcasts::V1::PlaylistsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should get index" do
    playlist = @user.playlists.create!(title: "Favorites")
    login_as @user
    get :index, format: :json
    assert_response :success
    data = parse_json

    assert_equal(playlist.id, data.first.safe_dig("id"))
    assert_equal(playlist.title, data.first.safe_dig("title"))
    assert_equal(playlist.sort_order, data.first.safe_dig("sort_order"))
    assert_not_nil data.first.safe_dig("created_at")
    assert_not_nil data.first.safe_dig("updated_at")
  end

  test "should create" do
    api_content_type
    login_as @user

    title = "Favorites"
    sort_order = "newest_first"

    assert_difference "Playlist.count", +1 do
      post :create, params: {title: title, sort_order: sort_order}, format: :json
      assert_response :success
    end

    assert_equal(title, @user.reload.playlists.first.title)
    assert_equal(sort_order, @user.reload.playlists.first.sort_order)
  end

  test "should delete" do
    api_content_type
    login_as @user

    playlist = @user.playlists.create!(title: "Favorites")

    assert_difference "Playlist.count", -1 do
      post :destroy, params: {id: playlist.id}, format: :json
      assert_response :success
    end
  end

  test "should update" do
    api_content_type
    login_as @user

    playlist = @user.playlists.create!(title: "Favorites")

    title = "Bookmarks"
    sort_order = "newest_first"


    patch :update, params: {id: playlist.id, title: title, title_updated_at: Time.now.iso8601(6), sort_order: sort_order, sort_order_updated_at: Time.now.iso8601(6)}, format: :json
    assert_response :success

    assert playlist.reload.title, title
    assert playlist.reload.sort_order, sort_order
    assert_equal("title", playlist.attribute_changes.first.name)
  end

  test "should not update" do
    api_content_type
    login_as @user

    title = "Favorites"
    playlist = @user.playlists.create!(title: title)

    patch :update, params: {id: playlist.id, title: "Bookmarks", title_updated_at: 1.second.ago.iso8601(6), sort_order: "newest_first", sort_order_updated_at: 1.second.ago.iso8601(6)}, format: :json
    assert_response :success

    assert playlist.reload.title, title
    assert playlist.reload.sort_order, "custom"
  end

end
