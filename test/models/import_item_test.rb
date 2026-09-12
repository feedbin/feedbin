require "test_helper"

class ImportItemTest < ActiveSupport::TestCase
  setup do
    import = users(:ben).imports.new(filename: "subscriptions.opml")
    @item = import.import_items.new(status: :failed, details: {
      title: "Example",
      xml_url: "http://Example.com/feed.xml",
      html_url: "http://Example.com/"
    })
    import.save!
  end

  test "host is lower-cased from the html url" do
    assert_equal "example.com", @item.reload.host
  end

  # favicons fallback: the legacy half goes with the favicons table.
  test "site_favicon prefers the images row and falls back to the favicons row" do
    assert_nil ImportItem.find(@item.id).site_favicon

    legacy = Favicon.create!(host: "example.com", url: "http://example.com/legacy.png")
    assert_equal legacy, ImportItem.find(@item.id).site_favicon

    row = create_favicon_row("example.com")
    assert_equal row, ImportItem.find(@item.id).site_favicon
  end
end
