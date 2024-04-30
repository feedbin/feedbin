require "test_helper"

class FeedImportFixerTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    import = @user.imports.create
    details = {
      xml_url: "http://www.example.com/atom.xml",
      tag: "Favorites",
      title: "My Title"
    }
    @import_item = import.import_items.create(details: details)
    @discovered_feed = DiscoveredFeed.create!(
      site_url: @import_item.site_url,
      feed_url: @import_item.feed_url
    )

    stub_request_file("atom.xml", @import_item.details[:xml_url])
  end

  test "should create subscription" do
    assert_difference -> { Subscription.count }, +1 do
      FeedImportFixer.new.perform(@user.id, @import_item.id, @discovered_feed.id)
    end

    assert_equal(@import_item.details[:title], Subscription.last.title)
  end
end
