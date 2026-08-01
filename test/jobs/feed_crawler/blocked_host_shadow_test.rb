require "test_helper"

module FeedCrawler
  class BlockedHostShadowTest < ActiveSupport::TestCase
    URL = "http://example.com/atom.xml".freeze

    def setup
      flush_redis
      @env = ENV.to_h.slice("SHADOW_BLOCK_PRIVATE_ADDRESSES", "FEEDKIT_CURL_HOSTS", "FEEDKIT_PROXIED_HOSTS")
      ENV["SHADOW_BLOCK_PRIVATE_ADDRESSES"] = "100"
    end

    # Callback form, not `def teardown`: webmock/minitest aliases teardown onto
    # Minitest::Test, so redefining the method here would drop WebMock.reset!
    # and let request counts leak between tests.
    teardown do
      %w[SHADOW_BLOCK_PRIVATE_ADDRESSES FEEDKIT_CURL_HOSTS FEEDKIT_PROXIED_HOSTS].each do |key|
        @env.key?(key) ? ENV[key] = @env[key] : ENV.delete(key)
      end
    end

    def test_does_nothing_when_unset
      ENV.delete("SHADOW_BLOCK_PRIVATE_ADDRESSES")
      request = stub_request_file("atom.xml", URL)

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 1, message: "control only"
    end

    def test_does_nothing_at_zero_percent
      ENV["SHADOW_BLOCK_PRIVATE_ADDRESSES"] = "0"
      request = stub_request_file("atom.xml", URL)

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 1, message: "control only"
    end

    def test_duplicates_the_request_when_sampled
      request = stub_request_file("atom.xml", URL)

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 2, message: "control and shadow"
    end

    def test_sends_an_identical_user_agent
      request = stub_request_file("atom.xml", URL).with(headers: {"User-Agent" => "Feedbin feed-id:1 - 10 subscribers"})

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 2
    end

    def test_shadows_a_feed_only_once_per_day
      request = stub_request_file("atom.xml", URL)

      crawl do
        Downloader.new.perform(1, URL, 10, {})
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_requested request, times: 3, message: "two controls, one shadow"
    end

    # The shadow must replay the conditional headers the control used, not the
    # ones the control's response just produced -- otherwise it 304s where the
    # control got a 200 and every verdict is a phantom diff.
    def test_replays_the_original_conditional_headers
      old_etag = "old-etag"
      new_etag = "new-etag"

      stub_request_file("atom.xml", URL, {headers: {"Etag" => new_etag}})

      crawl { Downloader.new.perform(1, URL, 10, {etag: old_etag}) }

      assert_requested :get, URL, headers: {"If-None-Match" => old_etag}, times: 2
      assert_not_requested :get, URL, headers: {"If-None-Match" => new_etag}
    end

    def test_reports_agree_when_both_succeed_identically
      stub_request_file("atom.xml", URL)

      line = crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=agree"
      assert_includes line, "control=ok"
      assert_includes line, "shadow=ok"
    end

    def test_reports_blocked_control_ok
      stub_request_file("atom.xml", URL)

      line = crawl(addresses: ["10.0.0.1"], shadow: blocked("example.com", "10.0.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=blocked_control_ok"
      assert_includes line, "rule=private"
      assert_includes line, "blocked_address=10.0.0.1"
      assert_includes line, "hop=origin"
    end

    def test_reports_blocked_control_error_when_the_feed_was_already_failing
      stub_request(:get, URL).to_return(status: 500)

      line = crawl(addresses: ["10.0.0.1"], shadow: blocked("example.com", "10.0.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=blocked_control_error"
      assert_includes line, "control_error=Feedkit::ServerError"
    end

    # The connect-path signal: the flag makes HTTP connect to addresses.first
    # rather than the hostname, so a working feed can start failing without
    # ever being blocked.
    def test_reports_regressed_when_the_shadow_fails_without_blocking
      stub_request_file("atom.xml", URL)

      line = crawl(shadow: -> { raise Feedkit::ConnectionError, "connection refused" }) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=regressed"
      assert_includes line, "shadow_error=Feedkit::ConnectionError"
    end

    def test_reports_recovered_when_only_the_control_failed
      stub_request(:get, URL).to_return({status: 500}, {status: 200, body: load_xml})

      line = crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=recovered"
    end

    def test_reports_content_diff_when_the_bodies_differ
      stub_request(:get, URL).to_return({status: 200, body: load_xml}, {status: 200, body: "#{load_xml}<!-- -->"})

      line = crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=content_diff"
    end

    # A host with one bad address and one good one is blocked outright, even
    # though TCPSocket would have reached the good one. This is the count that
    # says whether validate! needs changing before rollout.
    def test_counts_usable_public_addresses_on_a_blocked_host
      stub_request_file("atom.xml", URL)

      line = crawl(addresses: ["93.184.216.34", "fd00::1"], shadow: blocked("example.com", "fd00::1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "addresses=2"
      assert_includes line, "public_addresses=1"
      assert_includes line, "rule=private"
    end

    def test_attributes_the_matching_cidr_rule
      stub_request_file("atom.xml", URL)

      line = crawl(addresses: ["100.64.0.1"], shadow: blocked("example.com", "100.64.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "rule=100.64.0.0/10"
    end

    # A block on a redirect hop is the SSRF case, and reads very differently
    # from a feed that simply lives on a private address.
    def test_distinguishes_a_block_on_a_redirect_hop
      stub_request_file("atom.xml", URL)

      line = crawl(addresses: ["10.0.0.1"], shadow: blocked("internal.example.com", "10.0.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "hop=redirect"
      assert_includes line, "blocked_host=internal.example.com"
    end

    def test_records_the_address_family_handed_to_the_socket
      stub_request_file("atom.xml", URL)

      line = crawl(addresses: ["2606:2800:220:1::1", "93.184.216.34"]) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "first_family=inet6"
    end

    def test_skips_hosts_where_the_flag_is_a_no_op
      ENV["FEEDKIT_CURL_HOSTS"] = "example.com"

      line = capture_log do
        BlockedHostShadow.call(feed_id: 1, feed_url: URL, subscribers: 10, crawl_data: {})
      end

      assert_includes line, "verdict=no_op"
      assert_includes line, "path=curl"
      assert_not_requested :get, URL
    end

    def test_a_broken_shadow_never_breaks_the_crawl
      stub_request_file("atom.xml", URL)

      assert_difference -> { Parser.jobs.size }, +1 do
        assert_nothing_raised do
          crawl(shadow: -> { raise "boom" }) { Downloader.new.perform(1, URL, 10, {}) }
        end
      end
    end

    def test_does_not_enqueue_a_parser_or_persist_crawl_data_for_the_shadow
      feed = feeds(:daring_fireball)
      stub_request_file("atom.xml", feed.feed_url)

      assert_difference -> { Parser.jobs.size }, +1, "shadow must not enqueue a second parse" do
        crawl { Downloader.new.perform(feed.id, feed.feed_url, 10, {}) }
      end

      PersistCrawlData.new.perform
      assert_equal({}, feed.reload.crawl_data.to_h, "parse defers persistence; shadow must not change that")
    end

    private

    # Runs the block with DNS resolution stubbed and the shadow's log line
    # captured. `shadow:` replaces what the flag-on request does, which is the
    # only way to drive its outcome independently -- both requests share a URL,
    # so WebMock cannot tell them apart.
    def crawl(addresses: ["93.184.216.34"], shadow: nil, &block)
      resolved = addresses.map { |address| Addrinfo.ip(address) }

      Addrinfo.stub(:getaddrinfo, resolved) do
        capture_log do
          shadow ? with_shadow(shadow, &block) : block.call
        end
      end
    end

    def with_shadow(handler, &block)
      download = Feedkit::Request.method(:download)
      replacement = lambda do |url, **args|
        args[:block_private_addresses] ? handler.call : download.call(url, **args)
      end
      Feedkit::Request.stub(:download, replacement, &block)
    end

    def blocked(host, address)
      -> { raise Feedkit::BlockedHost, "#{host} resolves to blocked address: #{address}" }
    end

    def capture_log
      lines = []
      Sidekiq.logger.stub(:info, ->(message) { lines << message.to_s }) do
        yield
      end
      lines.find { |line| line.start_with?("BlockedHostShadow") }.to_s
    end
  end
end
