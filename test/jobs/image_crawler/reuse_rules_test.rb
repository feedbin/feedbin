require "test_helper"

module ImageCrawler
  class ReuseRulesTest < ActiveSupport::TestCase
    setup do
      flush_redis
      # skip? falls through to the site-wide check (a root-page fetch)
      # whenever the feed check misses; give every test a quiet root page.
      # Tests about the site-wide rule override this stub.
      stub_request(:get, "http://example.com/")
        .to_return(status: 200, body: "<html></html>", headers: {content_type: "text/html"})
      @url = "http://example.com/og.jpg"
      @image = Image.new_with_attributes(
        id: SecureRandom.hex,
        preset_name: "primary",
        image_urls: [],
        provider: ::Image.providers[:entry_preview],
        provider_id: 2,
        feed_id: 9,
        page_url: "http://example.com/article",
        meta_image_urls: [@url],
        original_url: @url
      )
    end

    def seed_row(provider_id:, feed_id: 9, url: @url, image_fingerprint: SecureRandom.hex(16))
      ::Image.create!(
        provider: :entry_preview,
        provider_id: provider_id.to_s,
        feed_id: feed_id,
        url: url,
        image_fingerprint: image_fingerprint,
        storage_path: ::Image.storage_path_for(url),
        width: 542, height: 304, bytesize: 12_345,
        placeholder_color: "aabbcc"
      )
    end

    test "skips a url already used by another entry in the feed" do
      rules = ReuseRules.new(@image)
      refute rules.skip?(@url)

      seed_row(provider_id: 1)
      assert rules.skip?(@url)
    end

    test "does not skip for the same entry, another feed, or non-meta candidates" do
      seed_row(provider_id: 2)
      refute ReuseRules.new(@image).skip?(@url), "an entry must not block itself on re-crawl"

      ::Image.delete_all
      seed_row(provider_id: 1, feed_id: 10)
      refute ReuseRules.new(@image).skip?(@url), "reuse is scoped per feed"

      ::Image.delete_all
      seed_row(provider_id: 1)
      @image.meta_image_urls = []
      refute ReuseRules.new(@image).skip?(@url), "inline img/media candidates are exempt"
    end

    test "skips a site-wide og:image" do
      stub_request(:get, "http://example.com/")
        .to_return(status: 200, body: %(<meta property="og:image" content="/og.jpg">), headers: {content_type: "text/html"})

      assert ReuseRules.new(@image).skip?(@url)
    end

    test "detects a repeated content fingerprint in the feed" do
      fingerprint = SecureRandom.hex(16)
      seed_row(provider_id: 1, url: "http://example.com/different-url.jpg", image_fingerprint: fingerprint)

      assert ReuseRules.new(@image).fingerprint_used_in_feed?(fingerprint)
      refute ReuseRules.new(@image).fingerprint_used_in_feed?(SecureRandom.hex(16))
    end
  end
end
