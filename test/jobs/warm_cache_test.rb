require "test_helper"

class WarmCacheTest < ActiveSupport::TestCase
  setup do
    clear_search
    @user = users(:ben)
  end

  test "caches entries" do
    WarmCache.new.perform(@user.feeds.first.id)
  end
end
