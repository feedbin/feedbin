require "test_helper"

module FaviconCrawler
  class FinderTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @page_url = URI.parse("http://example.com")
      @default_url = @page_url.dup
      @default_url.path = "/favicon.ico"
    end

    ONE_ICON = %(<html><head><link rel="icon" href="/icon-32.png"></head></html>)

    def find_jobs
      ImageCrawler::Pipeline::Find.jobs.map { it["args"].first }
    end

    def stub_homepage(body = ONE_ICON)
      stub_request(:get, @page_url).to_return(body: body, status: 200)
    end

    # Dual-store is over: the crawler discovers and schedules, and the
    # pipeline downloads and decides. Nothing here writes a favicons row.
    test "schedules both presets from one crawl, keyed by host" do
      stub_homepage(<<~HTML)
        <html><head>
          <link rel="icon" href="/icon-32.png">
          <link rel="apple-touch-icon" href="/touch-180.png">
        </head></html>
      HTML

      assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +2 do
        Finder.new.perform(@page_url.host)
      end

      favicon = find_jobs.find { it["preset_name"] == "favicon" }
      touch   = find_jobs.find { it["preset_name"] == "touch_icon" }

      assert_equal ::Image.providers[:website_favicon], favicon["provider"]
      assert_equal ::Image.kinds[:site_icon], favicon["kind"]
      assert_equal "example.com", favicon["provider_id"]
      assert_equal true, favicon["critical"]
      assert_equal ["http://example.com/icon-32.png", "http://example.com/touch-180.png", "http://example.com/favicon.ico"], favicon["image_urls"]

      assert_equal ::Image.providers[:website_touch_icon], touch["provider"]
      assert_equal ::Image.kinds[:site_icon], touch["kind"]
      assert_equal "example.com", touch["provider_id"]
      assert_equal ["http://example.com/touch-180.png"], touch["image_urls"]

      assert_nil Favicon.unscoped.find_by(host: @page_url.host)
      assert_not_requested :get, "http://example.com/icon-32.png"
      assert_not_requested :get, "http://example.com/touch-180.png"
      assert_not_requested :get, @default_url
    end

    test "schedules only the favicon preset when the host advertises no touch icon" do
      stub_homepage

      assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +1 do
        Finder.new.perform(@page_url.host)
      end

      assert_equal "favicon", find_jobs.last["preset_name"]
    end

    test "schedules the default location when the homepage cannot be fetched" do
      stub_request(:get, @page_url).to_timeout

      assert_nothing_raised do
        Finder.new.perform(@page_url.host)
      end

      assert_equal 1, find_jobs.size
      assert_equal ["http://example.com/favicon.ico"], find_jobs.last["image_urls"]
    end

    # A host advertising /favicon.ico yields that URL twice (discovered +
    # default fallback); schedule_icon dedupes on the string form.
    test "schedule_icon dedupes candidates that resolve to the same url" do
      stub_homepage(%(<html><head><link rel="icon" href="/favicon.ico"></head></html>))

      Finder.new.perform(@page_url.host)

      assert_equal ["http://example.com/favicon.ico"], find_jobs.last["image_urls"]
    end

    test "the host is lower-cased before anything keys on it" do
      stub_homepage

      Finder.new.perform("Example.COM")

      assert_equal "example.com", find_jobs.last["provider_id"]
      assert_equal "example.com-favicon", find_jobs.last["id"]
      assert_requested :get, @page_url
    end

    test "a blank host schedules nothing" do
      Finder.new.perform(nil)
      Finder.new.perform("")

      assert_empty ImageCrawler::Pipeline::Find.jobs
    end

    # One crawl per host per hour, whatever the number of subscribe events.
    test "the gate admits one crawl per host per hour" do
      stub_homepage

      Finder.new.perform(@page_url.host)
      Finder.new.perform(@page_url.host)

      assert_equal 1, ImageCrawler::Pipeline::Find.jobs.size
      assert_requested :get, @page_url, times: 1

      ttl = Sidekiq.redis { it.ttl("favicon_crawl:example.com") }
      assert_operator ttl, :>, 0
      assert_operator ttl, :<=, Finder::GATE.to_i
    end

    test "the gate is per host" do
      stub_homepage
      stub_request(:get, "http://other.example.com").to_return(body: ONE_ICON, status: 200)

      Finder.new.perform(@page_url.host)
      Finder.new.perform("other.example.com")

      assert_equal 2, ImageCrawler::Pipeline::Find.jobs.size
    end

    test "force skips the gate" do
      stub_homepage

      Finder.new.perform(@page_url.host)
      Finder.new.perform(@page_url.host, true)

      assert_equal 2, ImageCrawler::Pipeline::Find.jobs.size
    end

    test "a crawl and a gated crawl each count once" do
      stub_homepage
      counted = []

      Librato.stub(:increment, ->(name, *) { counted << name }) do
        Finder.new.perform(@page_url.host)
        Finder.new.perform(@page_url.host)
      end

      assert_equal ["favicon.crawl", "favicon.gated"], counted
    end

    test "critical false rides into the pipeline payload" do
      stub_homepage

      Finder.new.perform(@page_url.host, false, false)

      assert_equal false, find_jobs.last["critical"]
    end

    # The legacy write this rescue once protected is gone. An enqueue
    # failure is the job's failure: retry: false, logged by Sidekiq.
    test "an enqueue failure raises" do
      stub_homepage

      ImageCrawler::Pipeline::Find.stub(:perform_async, ->(*) { raise "redis hiccup" }) do
        assert_raises(RuntimeError) { Finder.new.perform(@page_url.host) }
      end
    end

    # Ordering is load-bearing: the first candidate that yields a usable
    # image wins. Four distinct rel values, so this pins only the
    # rel-position ordering and the /favicon.ico fallback.
    test "all_favicon_urls keeps its ordering and its default fallback" do
      stub_homepage(<<~HTML)
        <html><head>
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="icon" href="/icon-32.png" sizes="32x32">
          <link rel="shortcut icon" href="/shortcut.ico">
          <link rel="apple-touch-icon-precomposed" href="/touch-old.png">
        </head></html>
      HTML

      finder = Finder.new
      finder.instance_variable_set(:@host, @page_url.host)

      assert_equal [
        "http://example.com/shortcut.ico",
        "http://example.com/icon-32.png",
        "http://example.com/touch-180.png",
        "http://example.com/touch-old.png",
        "http://example.com/favicon.ico"
      ], finder.send(:all_favicon_urls).map(&:to_s)
    end

    test "touch_icon_urls is the apple subset in the same order, with no default fallback" do
      stub_homepage(<<~HTML)
        <html><head>
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="icon" href="/icon-32.png" sizes="32x32">
          <link rel="apple-touch-icon-precomposed" href="/touch-old.png">
        </head></html>
      HTML

      finder = Finder.new
      finder.instance_variable_set(:@host, @page_url.host)

      assert_equal [
        "http://example.com/touch-180.png",
        "http://example.com/touch-old.png"
      ], finder.send(:touch_icon_urls).map(&:to_s)
    end

    test "touch_icon_urls is empty when the host advertises no touch icon" do
      stub_homepage

      finder = Finder.new
      finder.instance_variable_set(:@host, @page_url.host)

      assert_empty finder.send(:touch_icon_urls)
    end

    # One page fetch, two lists. Deriving them separately would double the
    # homepage traffic for every crawl.
    test "the homepage is fetched once even when both lists are read" do
      request = stub_homepage(%(<html><head><link rel="apple-touch-icon" href="/touch.png"></head></html>))

      finder = Finder.new
      finder.instance_variable_set(:@host, @page_url.host)
      finder.send(:all_favicon_urls)
      finder.send(:touch_icon_urls)

      assert_requested request, times: 1
    end

    # The failed fetch must be memoized too; only the fetch count catches a
    # regression back to `||=`.
    test "both lists degrade to the default when the homepage cannot be fetched" do
      request = stub_request(:get, @page_url).to_timeout

      finder = Finder.new
      finder.instance_variable_set(:@host, @page_url.host)

      assert_equal ["http://example.com/favicon.ico"], finder.send(:all_favicon_urls).map(&:to_s)
      assert_empty finder.send(:touch_icon_urls)
      assert_requested request, times: 1
    end
  end
end
