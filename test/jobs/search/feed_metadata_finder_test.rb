require "test_helper"

module Search
  class FeedMetadataFinderTest < ActiveSupport::TestCase
    setup do
      @feed = feeds(:daring_fireball)
    end

    test "should get metadata" do
      stub_request_file("index.html", @feed.site_url)
      FeedMetadataFinder.new.perform(@feed.id)
      assert_equal("Title", @feed.reload.meta_title)
      assert_equal("Description", @feed.reload.meta_description)
      assert_not_nil(@feed.reload.meta_crawled_at)
    end
  end
end