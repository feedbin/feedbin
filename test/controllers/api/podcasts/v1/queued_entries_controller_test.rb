require "test_helper"
class Api::Podcasts::V1::QueuedEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    @queued_entry = @user.queued_entries.create!(entry: @entries.first, feed: @entries.first.feed)
    login_as @user
    get :index, format: :json
    assert_response :success
    data = parse_json
    assert_equal(@entries.first.id, data.first.dig("entry_id"))
    assert_equal(@entries.first.feed.id, data.first.dig("feed_id"))
    assert_not_nil data.first.dig("id")
    assert_not_nil data.first.dig("order")
    assert_not_nil data.first.dig("progress")
    assert_not_nil data.first.dig("created_at")
    assert_not_nil data.first.dig("updated_at")
  end

  test "should create" do
    api_content_type
    login_as @user

    assert_difference "QueuedEntry.count", +1 do
      post :create, params: {entry_id: @entries.first.id, progress: 10, order: 10}, format: :json
      assert_response :success
    end
  end

  test "should delete" do
    @queued_entry = @user.queued_entries.create!(entry: @entries.first, feed: @entries.first.feed)
    api_content_type
    login_as @user

    assert_difference "QueuedEntry.count", -1 do
      post :destroy, params: {id: @queued_entry.id}, format: :json
      assert_response :success
    end
  end
end
