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

  # The entry cache key also reads preview_image_record (Task 11), and
  # entry.processed_image? -- rendered for every row regardless of caching --
  # reads it too. @entries here is built directly (then .sort_by, which
  # converts it to an Array) rather than through Entry.entries_list, so
  # without its own preload this is a query per row. (A ".loaded?" assertion
  # cannot tell a preload from an N+1 that happens to run before it is
  # checked -- processed_image? would load the association either way -- so
  # this counts queries instead.)
  test "should preload the preview image the entry cache key reads" do
    login_as @user

    statements = capture_sql do
      get :index, xhr: true
    end

    assert_response :success
    assert_equal @updated.length, assigns(:entries).length
    images = statements.select { _1.match?(/FROM "images"/i) }
    assert_operator images.count, :<=, 1, "one images query for the whole page: #{images.count}"
  end
end
