require "test_helper"

class SearchIndexRemoveTest < ActiveSupport::TestCase
  setup do
    clear_search
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should remove entries from search index" do
    assert_difference "Entry.__elasticsearch__.client.count['count']", -@entries.count do
      SearchIndexRemove.new.perform(@entries.map(&:id))
      Entry.__elasticsearch__.refresh_index!
    end
  end
end
