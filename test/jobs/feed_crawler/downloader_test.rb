require "test_helper"

module FeedCrawler
  class DownloaderTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_schedule_feed_parser
      url = "http://example.com/atom.xml"
      stub_request_file("atom.xml", url)

      assert_equal 0, Sidekiq::Queues["feed_parser_#{Socket.gethostname}"].size
      Downloader.new.perform(1, url, 10)
      assert_equal 1, Sidekiq::Queues["feed_parser_#{Socket.gethostname}"].size

      Downloader.new.perform(1, url, 10)
      assert_equal 1, Sidekiq::Queues["feed_parser_#{Socket.gethostname}"].size
    end

    def test_should_schedule_critical_feed_parser
      url = "http://example.com/atom.xml"
      stub_request_file("atom.xml", url)

      assert_equal 0, Sidekiq::Queues["feed_parser_critical_#{Socket.gethostname}"].size
      DownloaderCritical.new.perform(1, url, 10, {})
      assert_equal 1, Sidekiq::Queues["feed_parser_critical_#{Socket.gethostname}"].size
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

      redirect_cache = RedirectCache.new(feed_id)
      Cache.write(redirect_cache.stable_key, {to: url_two})

      stub_request(:get, url_two)
      Downloader.new.perform(feed_id, url_one, 10)
    end

    def test_should_use_saved_redirect_with_basic_auth
      feed_id = 1
      username = "username"
      password = "password"
      url_one = "http://#{username}:#{password}@example.com/one"
      url_two = "http://example.com/two"

      redirect_cache = RedirectCache.new(feed_id)
      Cache.write(redirect_cache.stable_key, {to: url_two})

      stub_request(:get, url_two).with(headers: {"Authorization" => "Basic #{Base64.strict_encode64("#{username}:#{password}")}"})
      Downloader.new.perform(feed_id, url_one, 10)
    end

    def test_should_do_nothing_if_not_modified
      feed_id = 1
      etag = "etag"
      last_modified = "last_modified"
      Cache.write("refresher_http_#{feed_id}", {
        etag: etag,
        last_modified: last_modified,
        checksum: nil
      })

      url = "http://example.com/atom.xml"
      stub_request(:get, url).with(headers: {"If-None-Match" => etag, "If-Modified-Since" => last_modified}).to_return(status: 304)
      Downloader.new.perform(feed_id, url, 10)
      assert_equal 0, Sidekiq::Queues["feed_parser_critical_#{Socket.gethostname}"].size
    end

    def test_should_not_be_ok_after_error
      feed_id = 1

      url = "http://example.com/atom.xml"
      stub_request(:get, url).to_return(status: 429)

      Downloader.new.perform(feed_id, url, 10)

      refute FeedStatus.new(feed_id).ok?, "Should not be ok?"
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
  end
end