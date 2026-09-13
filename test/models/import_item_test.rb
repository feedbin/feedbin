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

  test "site_favicon is the host's images row" do
    assert_nil ImportItem.find(@item.id).site_favicon

    row = create_favicon_row("example.com")
    assert_equal row, ImportItem.find(@item.id).site_favicon
  end
end
