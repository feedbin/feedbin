require "test_helper"

class FeedParserTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @feed = Feed.first
  end

  def test_should_parse_xml
    assert_difference -> { FeedRefresherReceiver.jobs.size }, 1 do
      FeedParser.new.perform(@feed.id, @feed.feed_url, xml_path)
    end

    job = FeedRefresherReceiver.jobs.first
    feed = job["args"].first["feed"]

    assert_equal(@feed.feed_url, feed["feed_url"])
    assert_equal(@feed.id, feed["id"])
    assert_equal(5, job["args"].first["entries"].length)
  end

  def test_should_parse_json
    assert_difference -> { FeedRefresherReceiver.jobs.size }, 1 do
      FeedParser.new.perform(@feed.id, "http://example.com", json_path)
    end
  end

  def test_should_enqueue_error
    queue = Sidekiq::Queues['feed_downloader_critical']
    FeedParser.new.perform(@feed.id, "http://example.com", html_path)
    assert_equal("FeedCrawler::FeedStatusUpdate", queue.first["class"])
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
