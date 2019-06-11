require "test_helper"

class FeedImporterTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    import = @user.imports.create
    details = {
      xml_url: "http://www.example.com/atom.xml",
      tag: "Favorites",
      title: "My Title",
    }
    @import_item = import.import_items.create(details: details)
    stub_request_file("atom.xml", @import_item.details[:xml_url])
  end

  test "should create subscription" do
    assert_difference "Subscription.count", +1 do
      FeedImporter.new.perform(@import_item.id)
    end
    assert_equal("complete", @import_item.reload.status)
  end

  test "should tag subscription" do
    assert_difference "Tag.count", +1 do
      FeedImporter.new.perform(@import_item.id)
    end
  end

  test "should mark failed" do
    import = @user.imports.create
    details = { xml_url: "http://www.example.com/atom.xml" }
    import_item = import.import_items.create(details: details)
    stub_request(:get, import_item.details[:xml_url]).to_return(status: 404)
    FeedImporter.new.perform(import_item.id)
    assert_equal("failed", import_item.reload.status)
  end

  test "should title subscription" do
    FeedImporter.new.perform(@import_item.id)
    feed = Feed.where(feed_url: @import_item.details[:xml_url]).take!
    subscription = @user.subscriptions.where(feed: feed).take!
    assert_equal(@import_item.details[:title], subscription.title)
  end
end
