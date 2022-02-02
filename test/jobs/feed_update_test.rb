require "test_helper"

class FeedUpdateTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = create_entry(@feed)
  end

  test "should update feed" do
    stub_request_file("atom.xml", @feed.feed_url)
    response = Feedkit::Request.download(@feed.feed_url)
    parsed = response.parse
    entry = parsed.entries.first.to_entry
    @entry.update(public_id: entry[:public_id])

    FeedUpdate.new.perform(@feed.id)
    assert_equal(entry[:title], @entry.reload.title)
  end
end
