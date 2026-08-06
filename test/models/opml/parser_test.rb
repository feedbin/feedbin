require "test_helper"

module Opml
  class ParserTest < ActiveSupport::TestCase
    test "finds a self-closing outline" do
      feeds = Opml::Parser.parse(opml(%(<outline text="One" type="rss" xmlUrl="http://example.com/one.xml"/>)))

      assert_equal ["http://example.com/one.xml"], feeds.map { _1[:xml_url] }
    end

    test "finds an outline written with a closing tag" do
      feeds = Opml::Parser.parse(opml(<<~XML))
        <outline text="Paired" type="rss" xmlUrl="http://example.com/two.xml">
        </outline>
      XML

      assert_equal ["http://example.com/two.xml"], feeds.map { _1[:xml_url] },
        "the whitespace between the tags is a child node, which is not the same as a nested outline"
    end

    test "finds the feeds inside a folder" do
      feeds = Opml::Parser.parse(opml(<<~XML))
        <outline text="Folder" title="Folder">
          <outline text="One" type="rss" xmlUrl="http://example.com/one.xml"/>
          <outline text="Two" type="rss" xmlUrl="http://example.com/two.xml"/>
        </outline>
      XML

      assert_equal ["http://example.com/one.xml", "http://example.com/two.xml"], feeds.map { _1[:xml_url] }
      assert_equal ["Folder", "Folder"], feeds.map { _1[:tag] }
    end

    test "finds a folder that carries a feed of its own" do
      feeds = Opml::Parser.parse(opml(<<~XML))
        <outline text="Folder" title="Folder" type="rss" xmlUrl="http://example.com/folder.xml">
          <outline text="One" type="rss" xmlUrl="http://example.com/one.xml"/>
        </outline>
      XML

      assert_equal ["http://example.com/folder.xml", "http://example.com/one.xml"], feeds.map { _1[:xml_url] }
    end

    private

    def opml(body)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
          <head><title>Subscriptions</title></head>
          <body>
        #{body}
          </body>
        </opml>
      XML
    end
  end
end
