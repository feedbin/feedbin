require "test_helper"

module Search
  class FeedMetadataFinderTest < ActiveSupport::TestCase
    setup do
      @feed = feeds(:daring_fireball)
    end

    test "should get metadata" do
      stub_request_file("index.html", @feed.site_url)
      FeedMetadataFinder.new.perform(@feed.id)
      assert_equal("Title", @feed.reload.meta_title)
      assert_equal("Description", @feed.reload.meta_description)
      assert_not_nil(@feed.reload.meta_crawled_at)
    end

    test "fetches site metadata with Feedkit's private address check" do
      options = nil
      response = Struct.new(:body, :status).new("<html><head><title>Title</title></head></html>", HTTP::Response::Status.new(200))
      download = ->(_url, **args) do
        options = args
        response
      end
      Feedkit::Request.stub(:download, download) do
        FeedMetadataFinder.new.perform(@feed.id)
      end

      assert_equal true, options[:block_ssrf]
      assert_equal({connect: 5, write: 5, read: 5}, options[:timeout])
      assert_equal "Title", @feed.reload.meta_title
    end

    test "an unsolicited 304 keeps metadata and records the attempt" do
      @feed.update!(meta_title: "Existing title", meta_description: "Existing description")
      stub_request(:get, @feed.site_url).to_return(status: 304)

      FeedMetadataFinder.new.perform(@feed.id)

      assert_equal "Existing title", @feed.reload.meta_title
      assert_equal "Existing description", @feed.meta_description
      assert_operator @feed.meta_crawled_at.to_i, :>, 0
    end

    test "a private site is refused without losing existing metadata" do
      @feed.update!(site_url: "http://127.0.0.1:9/", meta_title: "Existing title")

      FeedMetadataFinder.new.perform(@feed.id)

      assert_equal "Existing title", @feed.reload.meta_title
      assert_operator @feed.meta_crawled_at.to_i, :>, 0
    end

    test "keeps existing metadata and records the attempt when a site fails" do
      @feed.update!(meta_title: "Existing title", meta_description: "Existing description")
      request = stub_request(:get, @feed.site_url).to_return(status: 500)

      FeedMetadataFinder.new.perform(@feed.id)
      FeedMetadataFinder.new.perform(@feed.id)

      assert_equal "Existing title", @feed.reload.meta_title
      assert_equal "Existing description", @feed.meta_description
      assert_operator @feed.meta_crawled_at.to_i, :>, 0
      assert_requested request, times: 1
    end

    test "records an attempt for an invalid site URL" do
      @feed.update!(site_url: "http://")

      FeedMetadataFinder.new.perform(@feed.id)

      assert_operator @feed.reload.meta_crawled_at.to_i, :>, 0
    end

    test "recovers metadata from a page with invalid declared encoding" do
      body = "<html><head><meta charset=\"EUC-JP\"><title>".b +
        "日本".encode("EUC-JP").b + "\xAD\xA1".b +
        " test</title></head></html>".b
      stub_request(:get, @feed.site_url).to_return(body: body, headers: {"Content-Type" => "text/html; charset=EUC-JP"})

      FeedMetadataFinder.new.perform(@feed.id)

      assert_equal "日本� test", @feed.reload.meta_title
      assert_operator @feed.meta_crawled_at.to_i, :>, 0
    end
  end
end
