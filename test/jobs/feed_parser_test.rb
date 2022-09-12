require "test_helper"

class FeedParserTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def test_should_parse_xml
    feed_url = "http://example.com"
    feed_id = 1
    assert_equal 0, Sidekiq::Queues['feed_refresher_receiver'].size
    FeedParser.new.perform(feed_id, feed_url, xml_path)
    assert_equal 1, Sidekiq::Queues['feed_refresher_receiver'].size

    job = Sidekiq::Queues['feed_refresher_receiver'].first
    feed = job["args"].first["feed"]

    assert_equal(feed_url, feed["feed_url"])
    assert_equal(feed_id, feed["id"])
    assert_equal(5, job["args"].first["entries"].length)
  end

  def test_should_parse_json
    assert_equal 0, Sidekiq::Queues['feed_refresher_receiver'].size
    FeedParser.new.perform(1, "http://example.com", json_path)
    assert_equal 1, Sidekiq::Queues['feed_refresher_receiver'].size
  end

  def test_should_be_not_feed
    feed_id = 1
    FeedParser.new.perform(feed_id, "http://example.com", html_path)
    assert_equal 1, Sidekiq::Queues['feed_downloader_critical'].size
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
