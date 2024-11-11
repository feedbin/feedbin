require "test_helper"

class Settings::ImportItemsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "replace feed" do
    login_as @user

    import = @user.imports.new
    item = import.import_items.new(
      status: :fixable,
      details: {
        title: "Example",
        xml_url: "http://example.com/feed",
        html_url: "http://example.com/"
      }
    )
    import.save
    discovered_feed = DiscoveredFeed.create!(
      site_url: item.site_url,
      feed_url: item.feed_url
    )

    assert_difference -> { FeedImportFixer.jobs.size }, +1 do
      post :update, params: {id: item.id, discovered_feed: {id: discovered_feed.id} }, xhr: true
      assert_response :success
    end
  end
end
