require "test_helper"

class ImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "keeps a folder name containing a comma intact" do
    import = @user.imports.create!(filename: "subscriptions.opml", xml: opml("News, Sports"))

    assert_equal ["News, Sports"], Array(import.import_items.first.details[:tag])
  end

  test "carries every folder a feed appeared in" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0">
        <head><title>Subscriptions</title></head>
        <body>
          <outline text="News, Sports" title="News, Sports">
            <outline text="Example" title="Example" type="rss" xmlUrl="http://www.example.com/atom.xml"/>
          </outline>
          <outline text="Daily" title="Daily">
            <outline text="Example" title="Example" type="rss" xmlUrl="http://www.example.com/atom.xml"/>
          </outline>
        </body>
      </opml>
    XML

    import = @user.imports.create!(filename: "subscriptions.opml", xml: xml)

    assert_equal ["News, Sports", "Daily"], Array(import.import_items.first.details[:tag])
  end

  test "tags the feed with the folder it came from, comma and all" do
    import = @user.imports.create!(filename: "subscriptions.opml", xml: opml("News, Sports"))
    item = import.import_items.first
    stub_request_file("atom.xml", item.details[:xml_url])

    FeedImporter.new.perform(item.id)

    assert_equal ["News, Sports"], @user.reload.feed_tags.map(&:name)
  end

  private

  def opml(folder)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0">
        <head><title>Subscriptions</title></head>
        <body>
          <outline text="#{folder}" title="#{folder}">
            <outline text="Example" title="Example" type="rss" xmlUrl="http://www.example.com/atom.xml" htmlUrl="http://www.example.com/"/>
          </outline>
        </body>
      </opml>
    XML
  end
end
