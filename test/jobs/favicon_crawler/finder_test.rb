require "test_helper"

module FaviconCrawler
  class FinderTest < ActiveSupport::TestCase
    setup do
      @page_url = URI.parse("http://example.com")
      @icon_url = @page_url.dup
      @icon_url.path = "/icons/favicon.ico"
      @default_url = @page_url.dup
      @default_url.path = "/favicon.ico"
    end

    test "should get favicon from icon link" do
      body = <<-eot
      <html>
          <head>
              <link rel="icon" href="#{@icon_url.path}">
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request_file("favicon.ico", @icon_url)

      Finder.new.perform(@page_url.host)

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    test "should get favicon from shortcut icon link" do
      body = <<-eot
      <html>
          <head>
              <link rel="shortcut icon" href="#{@icon_url}">
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request_file("favicon.ico", @icon_url)

      Finder.new.perform(@page_url.host)

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    test "should get favicon from default location" do
      body = <<-eot
      <html>
          <head>
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request_file("favicon.ico", @default_url)

      Finder.new.perform(@page_url.host)

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    test "should prefer larger favicon" do
      body = <<-eot
      <html>
          <head>
            <link rel="icon" type="image/png" sizes="32x32" href="/not_me_1" media="(prefers-color-scheme: light)"/>
            <link rel="icon" type="image/png" sizes="64x64" href="/pick_me" media="(prefers-color-scheme: light)"/>
            <link rel="icon" type="image/png" sizes="128x128" href="/not_me_2" media="(prefers-color-scheme: dark)"/>
            <link rel="apple-touch-icon" type="image/png" sizes="128x128" href="/not_me_3" media="(prefers-color-scheme: light)"/>
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")


      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)


      stub_request_file("favicon.ico", "http://example.com/pick_me")

      Finder.new.perform(@page_url.host)

      assert_requested :get, "http://example.com/pick_me"

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    test "should skip blank favicon" do
      body = <<-eot
      <html>
          <head>
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request_file("favicon-blank.ico", @default_url)

      Finder.new.perform(@page_url.host)

      assert_nil Favicon.unscoped.where(host: @page_url.host).take
    end

    test "should fall through to default location when homepage download errors" do
      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_timeout

      stub_request_file("favicon.ico", @default_url)

      assert_nothing_raised do
        Finder.new.perform(@page_url.host)
      end

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    test "should fall through to default location when icon download errors" do
      body = <<-eot
      <html>
          <head>
              <link rel="icon" href="#{@icon_url.path}">
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request(:get, @icon_url)
        .to_return(status: 429)

      stub_request_file("favicon.ico", @default_url)

      assert_nothing_raised do
        Finder.new.perform(@page_url.host)
      end

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    test "should skip a favicon that is not an image and keep looking" do
      body = <<-eot
      <html>
          <head>
              <link rel="icon" href="#{@icon_url.path}">
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      # PostScript reaches Ghostscript if it gets as far as magickload
      stub_request(:get, @icon_url)
        .to_return(body: "%!PS-Adobe-3.0\n/Times findfont", status: 200)

      stub_request_file("favicon.ico", @default_url)

      Finder.new.perform(@page_url.host)

      assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
    end

    # The crawl runs across the whole host table on a schedule, so anything it
    # leaves in the worker's tmpdir accumulates on every box until something
    # else sweeps /tmp.
    test "should remove the files it downloaded and resized" do
      body = <<-eot
      <html>
          <head>
              <link rel="icon" href="#{@icon_url.path}">
          </head>
      </html>
      eot

      stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
      stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

      stub_request(:get, @page_url)
        .to_return(body: body, status: 200)

      stub_request_file("favicon.ico", @icon_url)

      downloaded = nil
      build_processor = Processor.method(:new)
      capture = ->(favicon, host) {
        downloaded = favicon
        build_processor.call(favicon, host)
      }

      Processor.stub(:new, capture) do
        Finder.new.perform(@page_url.host)
      end

      assert_not_nil downloaded, "the crawl should have found a favicon to process"
      assert_not File.exist?(downloaded[:original]), "the downloaded favicon should not be left on disk"
      assert_not File.exist?(downloaded[:resized].to_path), "the resized favicon should not be left on disk"
    end

    test "should not save a favicon when nothing served is an image" do
      stub_request(:get, @page_url)
        .to_return(body: "<html><head></head></html>", status: 200)

      stub_request(:get, @default_url)
        .to_return(body: "%PDF-1.4\n1 0 obj", status: 200)

      Finder.new.perform(@page_url.host)

      assert_nil Favicon.unscoped.where(host: @page_url.host).take
    end

    # The legacy path consumes all_favicon_urls and its ordering is load-
    # bearing: the first candidate that yields a usable image wins. This pins
    # the whole list -- sorted by rel position in ICON_NAMES, then by declared
    # size descending, with /favicon.ico last -- so the refactor that adds
    # touch_icon_urls cannot quietly reorder it.
    test "all_favicon_urls keeps its ordering and its default fallback" do
      body = <<~HTML
        <html><head>
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="icon" href="/icon-32.png" sizes="32x32">
          <link rel="shortcut icon" href="/shortcut.ico">
          <link rel="apple-touch-icon-precomposed" href="/touch-old.png">
        </head></html>
      HTML
      stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_equal [
        "http://example.com/shortcut.ico",
        "http://example.com/icon-32.png",
        "http://example.com/touch-180.png",
        "http://example.com/touch-old.png",
        "http://example.com/favicon.ico"
      ], finder.send(:all_favicon_urls).map(&:to_s)
    end

    test "touch_icon_urls is the apple subset in the same order, with no default fallback" do
      body = <<~HTML
        <html><head>
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="icon" href="/icon-32.png" sizes="32x32">
          <link rel="apple-touch-icon-precomposed" href="/touch-old.png">
        </head></html>
      HTML
      stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_equal [
        "http://example.com/touch-180.png",
        "http://example.com/touch-old.png"
      ], finder.send(:touch_icon_urls).map(&:to_s)
    end

    test "touch_icon_urls is empty when the host advertises no touch icon" do
      body = %(<html><head><link rel="icon" href="/icon-32.png"></head></html>)
      stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_empty finder.send(:touch_icon_urls)
    end

    # One page fetch, two lists. Deriving them separately would double the
    # homepage traffic for every crawl.
    test "the homepage is fetched once even when both lists are read" do
      body = %(<html><head><link rel="apple-touch-icon" href="/touch.png"></head></html>)
      request = stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))
      finder.send(:all_favicon_urls)
      finder.send(:touch_icon_urls)

      assert_requested request, times: 1
    end

    test "both lists degrade to the default when the homepage cannot be fetched" do
      stub_request(:get, @page_url).to_timeout

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_equal ["http://example.com/favicon.ico"], finder.send(:all_favicon_urls).map(&:to_s)
      assert_empty finder.send(:touch_icon_urls)
    end
  end
end