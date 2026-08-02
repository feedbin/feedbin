require "test_helper"

module FeedCrawler
  class BlockedHostShadowTest < ActiveSupport::TestCase
    URL = "http://example.com/atom.xml".freeze

    PUBLIC_V4 = "93.184.216.34".freeze

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

      line = crawl(
        events: [resolved(["10.0.0.1"], blocked: ["10.0.0.1"])],
        shadow: blocked("example.com", ["10.0.0.1"])
      ) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=blocked_control_ok"
      assert_includes line, "rule=private"
      assert_includes line, "blocked_address=10.0.0.1"
      assert_includes line, "blocked_host=example.com"
      assert_includes line, "hop=origin"
    end

    def test_reports_blocked_control_error_when_the_feed_was_already_failing
      stub_request(:get, URL).to_return(status: 500)

      line = crawl(
        events: [resolved(["10.0.0.1"], blocked: ["10.0.0.1"])],
        shadow: blocked("example.com", ["10.0.0.1"])
      ) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=blocked_control_error"
      assert_includes line, "control_error=Feedkit::ServerError"
    end

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

    # A 304 carries an empty body, so comparing checksums alone reported two
    # servers disagreeing about freshness as a change in the feed.
    def test_separates_a_freshness_disagreement_from_a_content_change
      stub_request(:get, URL).to_return({status: 200, body: load_xml}, {status: 304})

      line = crawl { Downloader.new.perform(1, URL, 10, {etag: "etag"}) }

      assert_includes line, "verdict=conditional_diff"
      assert_not_includes line, "verdict=content_diff"
    end

    # http.rb filters blocked addresses rather than rejecting the host, so a
    # stray link-local record beside a working one no longer takes the feed
    # down. public_addresses is what proves the filtering is still happening.
    def test_reports_the_usable_addresses_of_a_partially_blocked_host
      stub_request_file("atom.xml", URL)

      line = crawl(events: [resolved([PUBLIC_V4, "fe80::1"], blocked: ["fe80::1"])]) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=agree"
      assert_includes line, "addresses=2"
      assert_includes line, "public_addresses=1"
    end

    def test_attributes_the_matching_cidr_rule
      stub_request_file("atom.xml", URL)

      line = crawl(
        events: [resolved(["100.64.0.1"], blocked: ["100.64.0.1"])],
        shadow: blocked("example.com", ["100.64.0.1"])
      ) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "rule=100.64.0.0/10"
    end

    # A block on a redirect hop is the SSRF case, and reads very differently
    # from a feed that simply lives on a private address.
    def test_distinguishes_a_block_on_a_redirect_hop
      stub_request_file("atom.xml", URL)

      line = crawl(
        events: [resolved([PUBLIC_V4]), resolved(["10.0.0.1"], blocked: ["10.0.0.1"])],
        shadow: blocked("internal.example.com", ["10.0.0.1"])
      ) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "hop=redirect"
      assert_includes line, "blocked_host=internal.example.com"
      assert_includes line, "hops=2"
    end

    def test_records_the_family_of_the_address_the_socket_used
      stub_request_file("atom.xml", URL)

      line = crawl(events: [resolved(["2606:2800:220:1::1"]), dial("2606:2800:220:1::1")]) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "first_family=inet6"
    end

    # The signal that answers whether address selection costs connections or
    # saves them: a non-zero index only happens because an earlier one failed.
    def test_reports_when_a_later_address_rescued_the_connection
      stub_request_file("atom.xml", URL)

      events = [
        resolved(["198.51.100.1", PUBLIC_V4]),
        dial("198.51.100.1", index: 0, total: 2, error: Errno::ECONNREFUSED.new),
        dial(PUBLIC_V4, index: 1, total: 2)
      ]

      line = crawl(events: events) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "dials=2"
      assert_includes line, "fallback=true"
      assert_includes line, "dials_failed=1"
    end

    def test_does_not_claim_fallback_when_the_first_address_connected
      stub_request_file("atom.xml", URL)

      line = crawl(events: [resolved([PUBLIC_V4]), dial(PUBLIC_V4)]) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "dials=1"
      assert_includes line, "fallback=false"
    end

    # Summed across hops, so a redirect chain reports what the whole request
    # spent resolving rather than only its last hop.
    def test_sums_resolution_time_across_hops
      stub_request_file("atom.xml", URL)

      events = [resolved([PUBLIC_V4], duration: 0.012), resolved([PUBLIC_V4], duration: 0.008)]

      line = crawl(events: events) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "dns_ms=20"
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

    # Runs the block with the shadow's log line captured. `events:` are replayed
    # into the blocklist observer, standing in for what http.rb reports; WebMock
    # replaces HTTP::Client#perform, so no connection is built and the real
    # blocklist never runs. `shadow:` replaces what the flag-on request does,
    # which is the only way to drive its outcome -- both requests share a URL,
    # so WebMock cannot tell them apart.
    def crawl(events: nil, shadow: nil, &block)
      events ||= [resolved([PUBLIC_V4]), dial(PUBLIC_V4)]

      capture_log { with_shadow(events, shadow, &block) }
    end

    def with_shadow(events, handler, &block)
      download = Feedkit::Request.method(:download)

      replacement = lambda do |url, **args|
        next download.call(url, **args) unless args[:block_private_addresses]

        events.each { |event, data| args[:blocklist_observer]&.call(event, data) }
        handler ? handler.call : download.call(url, **args)
      end

      Feedkit::Request.stub(:download, replacement, &block)
    end

    def resolved(addresses, blocked: [], duration: 0.001)
      [:resolved, {
        host:      "example.com",
        addresses: addresses,
        allowed:   addresses - blocked,
        blocked:   blocked,
        duration:  duration
      }]
    end

    def dial(address, index: 0, total: 1, error: nil)
      [:connect, {
        host:     "example.com",
        address:  address,
        index:    index,
        total:    total,
        duration: 0.001,
        error:    error
      }]
    end

    def blocked(host, addresses)
      lambda do
        raise Feedkit::BlockedHost.new(
          "#{host} resolves only to blocked addresses: #{addresses.join(", ")}",
          host: host, addresses: addresses, blocked: addresses
        )
      end
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
