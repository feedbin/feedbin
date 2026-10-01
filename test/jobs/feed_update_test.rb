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

    options = nil
    download = ->(_url, **args) do
      options = args
      response
    end
    Feedkit::Request.stub(:download, download) do
      FeedUpdate.new.perform(@feed.id)
    end

    assert_equal true, options[:block_ssrf]
    assert_equal(entry[:title], @entry.reload.title)
  end

  test "an upstream failure leaves the existing feed available" do
    stub_request(:get, @feed.feed_url).to_return(status: 503)

    FeedUpdate.new.perform(@feed.id)

    assert Feed.exists?(@feed.id)
  end
end
