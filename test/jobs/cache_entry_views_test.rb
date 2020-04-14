require "test_helper"

class CacheEntryViewsTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @entry = @entries.first
  end

  test "caches entries" do
    CacheEntryViews.new.perform(@entry.id)
  end
end
