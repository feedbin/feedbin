require "test_helper"

module FeedCrawler
  class DownloaderTest < ActiveSupport::TestCase
    def setup
      flush_redis
      @feed = feeds(:daring_fireball)
    end

    def test_should_persist_crawl_data_on_parse
      etag = "etag"
      last_modified = "last_modified"
      download_fingerprint = "694b08e"

      stub_request(:get, /dhy5vgj5baket\.cloudfront\.net/).to_return(status: 404)
      stub_request_file("atom.xml", @feed.feed_url,{
        headers: {
          "Etag" => etag,
          "Last-Modified" => last_modified
        }
      })

      Sidekiq::Testing.inline! do
        Downloader.perform_async(@feed.id, @feed.feed_url, 10, {})
      end

      crawl_data = @feed.reload.crawl_data

      assert_equal(etag, crawl_data.etag)
      assert_equal(last_modified, crawl_data.last_modified)
      assert_equal(download_fingerprint, crawl_data.download_fingerprint)
      assert_not_nil(crawl_data.last_uncached_download)
      assert_not_nil(crawl_data.downloaded_at)

      refute crawl_data.ignore_http_caching?, "should be false with recent uncached download"

      Downloader.new.perform(@feed.id, @feed.feed_url, 10, @feed.reload.crawl_data.to_h)
      assert_equal 0, Parser.jobs.size, "should be empty because fingerprint will match"
    end

    def test_should_persist_crawl_data_on_changed_conditional_headers_and_unchanged_fingerprint
      new_etag = "new_etag"
      new_last_modified = "new_last_modified"
      download_fingerprint = "694b08e" # unchanged

      existing_crawl_data = CrawlData.new({
        etag: "old_etag",
        last_modified: "old_last_modified",
        checksum: download_fingerprint,
        last_uncached_download: 1.hour.ago.to_i  # recent to not invoke ignore_http_caching?
      })
      refute existing_crawl_data.ignore_http_caching?, "should be false to test correctly"

      stub_request(:get, /dhy5vgj5baket\.cloudfront\.net/).to_return(status: 404)
      stub_request_file("atom.xml", @feed.feed_url,{
        headers: {
          "Etag" => new_etag,
          "Last-Modified" => new_last_modified
        }
      })

      Sidekiq::Testing.inline! do
        Downloader.perform_async(@feed.id, @feed.feed_url, 10, existing_crawl_data.to_h)
      end

      assert_equal 0, Parser.jobs.size, "should be empty because fingerprint will match"

      crawl_data = @feed.reload.crawl_data
      assert_equal(new_etag, crawl_data.etag)
      assert_equal(new_last_modified, crawl_data.last_modified)
      assert_equal(download_fingerprint, crawl_data.download_fingerprint) # should not change
      assert_in_delta(Time.now, Time.at(crawl_data.downloaded_at), 1.0)
    end

    def test_should_not_persist_crawl_before_parse
      stub_request(:get, /dhy5vgj5baket\.cloudfront\.net/).to_return(status: 404)
      stub_request_file("atom.xml", @feed.feed_url)
      Downloader.new.perform(@feed.id, @feed.feed_url, 10, {})
      PersistCrawlData.new.perform
      assert_equal({}, @feed.reload.crawl_data.to_h)
    end

    def test_should_schedule_feed_parser
      stub_request_file("atom.xml", @feed.feed_url)

      assert_difference -> { Parser.jobs.size }, +1 do
        Downloader.new.perform(@feed.id, @feed.feed_url, 10)
      end
    end

    def test_should_schedule_critical_feed_parser
      url = "http://example.com/atom.xml"
      stub_request_file("atom.xml", url)

      assert_difference -> { ParserCritical.jobs.size }, +1 do
        DownloaderCritical.new.perform(1, url, 10, {})
      end
    end

    def test_should_send_user_agent
      url = "http://example.com/atom.xml"
      stub_request_file("atom.xml", url).with(headers: {"User-Agent" => "Feedbin feed-id:1 - 10 subscribers"})
      Downloader.new.perform(1, url, 10)
    end

    def test_should_send_authorization
      username = "username"
      password = "password"
      url = "http://#{username}:#{password}@example.com/atom.xml"

      stub_request(:get, "http://example.com/atom.xml").with(headers: {"Authorization" => "Basic #{Base64.strict_encode64("#{username}:#{password}")}"})
      Downloader.new.perform(1, url, 10)
    end

    def test_should_use_saved_redirect
      feed_id = 1
      url_one = "http://example.com/one"
      url_two = "http://example.com/two"

      data = CrawlData.new(redirected_to: url_two)

      stub_request(:get, url_two)
      Downloader.new.perform(feed_id, url_one, 10, data.to_h)
    end

    def test_should_use_saved_redirect_with_basic_auth
      feed_id = 1
      username = "username"
      password = "password"
      url_one = "http://#{username}:#{password}@example.com/one"
      url_two = "http://example.com/two"

      data = CrawlData.new(redirected_to: url_two)

      stub_request(:get, url_two).with(headers: {"Authorization" => "Basic #{Base64.strict_encode64("#{username}:#{password}")}"})
      Downloader.new.perform(feed_id, url_one, 10, data.to_h)
    end

    def test_should_do_nothing_if_not_modified
      feed_id = 1
      etag = "etag"
      last_modified = "last_modified"

      data = CrawlData.new({
        etag: etag,
        last_modified: last_modified,
        checksum: nil,
        last_uncached_download: Time.now.to_i
      })

      url = "http://example.com/atom.xml"
      stub_request(:get, url).with(headers: {"If-None-Match" => etag, "If-Modified-Since" => last_modified}).to_return(status: 304)
      Downloader.new.perform(feed_id, url, 10, data.to_h)
      assert_equal 0, ParserCritical.jobs.size
    end

    def test_should_not_be_ok_after_error
      retry_after = 1000
      time = Time.now.to_i + retry_after

      stub_request(:get, @feed.feed_url).to_return(status: 429, headers: {"Retry-After" => retry_after})

      Downloader.new.perform(@feed.id, @feed.feed_url, 10, {})
      migration = PersistCrawlData.new
      migration.jid = SecureRandom.hex
      migration.perform

      refute @feed.reload.crawl_data.ok?(@feed.feed_url), "Should not be ok?"
      assert_equal(time, @feed.reload.crawl_data.last_error["retry_after"])

      job = Downloader.new
      job.critical = true
      job.perform(@feed.id, @feed.feed_url, 10, @feed.reload.crawl_data.to_h)

      migration = PersistCrawlData.new
      migration.jid = SecureRandom.hex
      migration.perform

      assert_equal(2, @feed.reload.crawl_data.error_count)
    end

    def test_should_follow_redirects
      first_url = "http://www.example.com"
      last_url = "#{first_url}/final"

      response = {
        status: 301,
        headers: {
          "Location" => "/final"
        }
      }
      stub_request(:get, first_url).to_return(response)
      stub_request(:get, last_url)

      Downloader.new.perform(1, first_url, 10)
    end

    def test_should_save_redirected_to
      last_url = URI.join(@feed.feed_url, "/final")

      response = {
        status: 301,
        headers: {
          "Location" => "/final"
        }
      }
      stub_request(:get, @feed.feed_url).to_return(response)
      stub_request(:get, last_url)

      (RedirectCache::PERSIST_AFTER).times do
        Downloader.new.perform(@feed.id, @feed.feed_url, 10, @feed.reload.crawl_data.to_h)
        migration = PersistCrawlData.new
        migration.jid = SecureRandom.hex
        migration.perform
        assert_nil(@feed.reload.crawl_data.redirected_to)
      end

      stub_request(:get, /dhy5vgj5baket\.cloudfront\.net/).to_return(status: 404)

      Sidekiq::Testing.inline! do
        Downloader.perform_async(@feed.id, @feed.feed_url, 10, @feed.reload.crawl_data.to_h)
      end

      assert_equal(last_url.to_s, @feed.reload.crawl_data.redirected_to)
    end
  end
end