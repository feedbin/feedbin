require "test_helper"

module ImageCrawler
  class RootMetaImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    def stub_root(body)
      stub_request(:get, "http://example.com/").to_return(status: 200, body: body, headers: {content_type: "text/html"})
    end

    test "detects a site-wide og:image" do
      stub_root %(<html><head><meta property="og:image" content="/site-wide.jpg"></head></html>)

      assert RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/article")
      refute RootMetaImage.site_wide?("http://example.com/article-specific.jpg", "http://example.com/article")
    end

    test "never flags the root page's own image" do
      refute RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/")
      assert_not_requested :get, "http://example.com/"
    end

    test "caches the root page lookup" do
      stub_root %(<html><head><meta property="og:image" content="/site-wide.jpg"></head></html>)

      2.times { RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/article") }
      assert_requested :get, "http://example.com/", times: 1
    end

    test "caches failures as empty" do
      stub_request(:get, "http://example.com/").to_return(status: 500)

      refute RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/article")
      refute RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/other")
      assert_requested :get, "http://example.com/", times: 1
    end

    test "handles missing page context" do
      refute RootMetaImage.site_wide?("http://example.com/a.jpg", nil)
      refute RootMetaImage.site_wide?("http://example.com/a.jpg", "")
    end
  end
end
