require "test_helper"

module FeedCrawler
  class ParserTest < ActiveSupport::TestCase
    setup do
      Sidekiq::Worker.clear_all
      @feed = Feed.first
    end

    def test_should_parse_xml
      assert_nil(@feed.last_change_check)
      assert_difference -> { Receiver.jobs.size }, 1 do
        Parser.new.perform(@feed.id, xml_path)
      end
      assert_not_nil(@feed.reload.last_change_check)

      job = Receiver.jobs.first
      feed = job["args"].first["feed"]

      assert_equal(@feed.feed_url, feed["feed_url"])
      assert_equal(@feed.id, feed["id"])
      assert_equal(5, job["args"].first["entries"].length)
    end

    def test_should_parse_json
      assert_difference -> { Receiver.jobs.size }, 1 do
        Parser.new.perform(@feed.id, json_path)
      end
    end

    def test_should_save_not_feed_error
      Parser.new.perform(@feed.id, html_path)
      assert_equal("Feedkit::NotFeed", @feed.reload.crawl_data.last_error["class"])
    end

    def test_should_clear_error
      Parser.new.perform(@feed.id, html_path)
      refute @feed.reload.crawl_data.ok?

      Parser.new.perform(@feed.id, xml_path, nil, @feed.reload.crawl_data.to_h)
      assert @feed.reload.crawl_data.ok?
    end

    private

    def xml_path
      tempfile_path(File.expand_path("test/support/www/atom.xml"))
    end

    def json_path
      tempfile_path(File.expand_path("test/support/www/feed.json"))
    end

    def html_path
      tempfile_path(File.expand_path("test/support/www/index.html"))
    end

    def tempfile_path(original_path)
      tempfile = Tempfile.new
      tempfile.close

      FileUtils.cp original_path, tempfile.path
      tempfile.path
    end

  end
end