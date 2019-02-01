require "test_helper"

class EntryIdCacheTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries.order(published: :desc)
  end

  test "should get entries" do
    cache = EntryIdCache.new(@user.id, @feeds.map(&:id))
    entries = cache.page(1)
    assert_equal(@entries.map(&:id), entries.map(&:id))
  end

  test "should paginate" do
    old_value = WillPaginate.per_page
    WillPaginate.per_page = 1

    cache = EntryIdCache.new(@user.id, @feeds.map(&:id))
    page_1 = cache.page(1)

    ids = 1.upto(page_1.total_pages).each_with_object([]) { |page, array|
      results = cache.page(page)
      array.push(results.first.id)
    }

    assert_equal(@entries.map(&:id), ids)

    WillPaginate.per_page = old_value
  end
end
