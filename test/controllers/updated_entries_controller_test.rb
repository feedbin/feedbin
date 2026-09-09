require "test_helper"

class UpdatedEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @updated = @entries.each do |entry|
      UpdatedEntry.create_from_owners(@user.id, entry)
    end
  end

  test "should get index" do
    login_as @user
    get :index, xhr: true
    assert_response :success
    assert_equal @updated.length, assigns(:entries).length
  end

  # @entries is built directly (then .sort_by materializes it), not through
  # entries_list, so it needs its own preload. Counts queries -- .loaded?
  # cannot tell a preload from an early N+1.
  test "should preload the preview image the entry cache key reads" do
    login_as @user

    statements = capture_sql do
      get :index, xhr: true
    end

    assert_response :success
    assert_equal @updated.length, assigns(:entries).length
    images = statements.select { it.match?(/FROM "images"/i) }
    assert_operator images.count, :<=, 3, "flat images queries for the whole page (preview_image_record, link_image_record, icon_image_record): #{images.count}"
  end
end
