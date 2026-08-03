require "test_helper"

module FeedCrawler
  class SsrfShadowTest < ActiveSupport::TestCase
    URL = "http://example.com/atom.xml".freeze

    PUBLIC_V4 = "93.184.216.34".freeze

    ENV_KEYS = %w[SHADOW_BLOCK_SSRF FEEDKIT_CURL_HOSTS FEEDKIT_PROXIED_HOSTS].freeze

    def setup
      flush_redis
      @env = ENV.to_h.slice(*ENV_KEYS)
      ENV["SHADOW_BLOCK_SSRF"] = "100"
    end

    # Callback form, not `def teardown`: webmock/minitest aliases teardown onto
    # Minitest::Test, so redefining the method here would drop WebMock.reset!
    # and let request counts leak between tests.
    teardown do
      ENV_KEYS.each { |key| @env.key?(key) ? ENV[key] = @env[key] : ENV.delete(key) }
    end

    def test_does_nothing_when_unset
      ENV.delete("SHADOW_BLOCK_SSRF")
      request = stub_request_file("atom.xml", URL)

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 1, message: "control only"
    end

    def test_does_nothing_at_zero_percent
      ENV["SHADOW_BLOCK_SSRF"] = "0"
      request = stub_request_file("atom.xml", URL)

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 1, message: "control only"
    end

    def test_duplicates_the_request_when_sampled
      request = stub_request_file("atom.xml", URL)

      crawl { Downloader.new.perform(1, URL, 10, {}) }

      assert_requested request, times: 2, message: "control and shadow"
    end

    def test_asks_feedkit_to_block_ssrf_on_the_shadow_only
      stub_request_file("atom.xml", URL)
      seen = []

      crawl(observe: ->(args) { seen << args[:block_ssrf] }) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_equal [nil, true], seen, "control unblocked, shadow blocked"
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

      line = crawl(resolved: ["10.0.0.1"], shadow: blocked("example.com", "10.0.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=blocked_control_ok"
      assert_includes line, "rule=private"
      assert_includes line, "blocked_address=10.0.0.1"
      assert_includes line, "blocked_host=example.com"
      assert_includes line, "hop=origin"
      assert_includes line, "public_addresses=0"
    end

    def test_reports_blocked_control_error_when_the_feed_was_already_failing
      stub_request(:get, URL).to_return(status: 500)

      line = crawl(resolved: ["10.0.0.1"], shadow: blocked("example.com", "10.0.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=blocked_control_error"
      assert_includes line, "control_error=Feedkit::ServerError"
    end

    def test_attributes_the_matching_cidr_rule
      stub_request_file("atom.xml", URL)

      line = crawl(resolved: ["100.64.0.1"], shadow: blocked("example.com", "100.64.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "rule=100.64.0.0/10"
    end

    # A block on a redirect hop is the SSRF case, and reads very differently
    # from a feed that simply lives on a private address.
    def test_distinguishes_a_block_on_a_redirect_hop
      stub_request_file("atom.xml", URL)

      line = crawl(resolved: ["10.0.0.1"], shadow: blocked("internal.example.com", "10.0.0.1")) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "hop=redirect"
      assert_includes line, "blocked_host=internal.example.com"
    end

    # Feedkit rejects an address rather than the host, so a block reported next
    # to a usable public address would mean that filtering broke.
    def test_counts_the_publicly_routable_addresses
      stub_request_file("atom.xml", URL)

      line = crawl(resolved: [PUBLIC_V4, "10.0.0.1"]) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "addresses=2"
      assert_includes line, "public_addresses=1"
    end

    # Resolv is asked for both families and keeps at most two of each, then
    # races them, so both counts matter and no single "first" address decides
    # what gets used.
    def test_counts_the_candidates_of_each_family
      stub_request_file("atom.xml", URL)

      line = crawl(resolved: ["2606:2800:220:1::1", "2606:2800:220:1::2", PUBLIC_V4]) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "v6=2"
      assert_includes line, "v4=1"
    end

    def test_reports_regressed_when_the_shadow_fails_without_blocking
      stub_request_file("atom.xml", URL)

      line = crawl(shadow: -> { raise Feedkit::ConnectionError, "connection refused" }) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=regressed"
      assert_includes line, "shadow_error=Feedkit::ConnectionError"
      assert_includes line, "dns_failed=false"
    end

    # Resolv swallows its own errors, so a resolution that produced nothing
    # arrives as a connection error rather than a timeout. That was the dominant
    # failure last run, so it gets counted rather than buried.
    def test_separates_a_failed_resolution_from_other_connection_errors
      stub_request_file("atom.xml", URL)
      failure = -> { raise Feedkit::ConnectionError, "failed to connect: no address for example.com" }

      line = crawl(shadow: failure) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=regressed"
      assert_includes line, "dns_failed=true"
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

    def test_separates_a_freshness_disagreement_from_a_content_change
      stub_request(:get, URL).to_return({status: 200, body: load_xml}, {status: 304})

      line = crawl { Downloader.new.perform(1, URL, 10, {etag: "etag"}) }

      assert_includes line, "verdict=conditional_diff"
      assert_not_includes line, "verdict=content_diff"
    end

    # Blocking skips the curl shortcut, so these feeds change client rather than
    # being exempt. They are still shadowed -- that comparison is the point --
    # but a difference on them is transport, not address checking.
    # Curl keeps its shortcut when blocking, because that list is
    # operator-curated and known safe. Shadowing those feeds would compare curl
    # against curl and pay for a duplicate fetch to learn nothing.
    def test_skips_curl_hosts
      ENV["FEEDKIT_CURL_HOSTS"] = "example.com"

      line = capture_log do
        SsrfShadow.call(feed_id: 1, feed_url: URL, subscribers: 10, crawl_data: {})
      end

      assert_includes line, "verdict=no_op"
      assert_includes line, "path=curl"
      assert_not_requested :get, URL
    end

    # Feedkit rewrites these to a host the operator chose, so no check applies.
    def test_skips_proxied_hosts
      ENV["FEEDKIT_PROXIED_HOSTS"] = "example.com"

      line = capture_log do
        SsrfShadow.call(feed_id: 1, feed_url: URL, subscribers: 10, crawl_data: {})
      end

      assert_includes line, "verdict=no_op"
      assert_includes line, "path=proxy"
      assert_not_requested :get, URL
    end

    # A rejection and a rate limit both arrive as Feedkit::ClientError but call
    # for different responses, so the status has to survive into the log.
    def test_records_the_status_behind_a_failed_shadow
      stub_request_file("atom.xml", URL)
      stub_request(:get, "http://blocked.example.com/").to_return(status: 403)
      rejection = -> { Feedkit::Request.download("http://blocked.example.com/") }

      line = crawl(shadow: rejection) { Downloader.new.perform(1, URL, 10, {}) }

      assert_includes line, "verdict=regressed"
      assert_includes line, "shadow_error=Feedkit::ClientError"
      assert_includes line, "shadow_status=403"
    end

    # Both sides failing is agreement. Now that an error carries a status,
    # comparing statuses here would read two failures as a freshness change.
    def test_treats_two_failures_as_agreement
      stub_request(:get, URL).to_return(status: 500)

      line = crawl(shadow: -> { raise Feedkit::ServerError.new("500", nil) }) do
        Downloader.new.perform(1, URL, 10, {})
      end

      assert_includes line, "verdict=agree"
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

    # Runs the block with the shadow's log line captured and Feedkit's resolver
    # stubbed. Both requests share a URL, so replacing the download is the only
    # way to drive the shadow's outcome independently of the control's:
    # `shadow:` supplies its result, `observe:` just watches the arguments.
    def crawl(resolved: [PUBLIC_V4], shadow: nil, observe: nil, &block)
      capture_log do
        # IPAddr, not String: that is what Feedkit's resolver hands back, and
        # stubbing strings here hid a production bug where every address parsed
        # to nil and each one was counted as publicly routable.
        Feedkit::PrivateAddressCheck::Socket.stub(:addresses, resolved.map { |address| IPAddr.new(address) }) do
          if shadow || observe
            with_download(shadow, observe, &block)
          else
            block.call
          end
        end
      end
    end

    def with_download(shadow, observe, &block)
      download = Feedkit::Request.method(:download)

      replacement = lambda do |url, **args|
        observe&.call(args)
        next download.call(url, **args) unless args[:block_ssrf]

        shadow ? shadow.call : download.call(url, **args.except(:block_ssrf))
      end

      Feedkit::Request.stub(:download, replacement, &block)
    end

    def blocked(host, address)
      -> { raise Feedkit::PrivateNetworkAddress, "#{host} resolves to a private address: #{address}" }
    end

    # Tolerates the block form, `logger.info { "..." }`, which other callers use
    # and which a one-argument stub would reject with an ArgumentError.
    def capture_log
      lines = []
      Sidekiq.logger.stub(:info, ->(*args, &block) { lines << (args.first || block&.call).to_s }) do
        yield
      end
      lines.find { |line| line.start_with?("SsrfShadow") }.to_s
    end
  end
end
