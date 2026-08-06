require "test_helper"

class UrlCacheTest < ActiveSupport::TestCase
  test "cache_key is deterministic for the same url and options" do
    a = UrlCache.new("https://example.com", {accept: "text/html"})
    b = UrlCache.new("https://example.com", {accept: "text/html"})
    assert_equal a.cache_key, b.cache_key
  end

  test "cache_key differs when the url differs" do
    a = UrlCache.new("https://example.com")
    b = UrlCache.new("https://other.example.com")
    refute_equal a.cache_key, b.cache_key
  end

  test "cache_key differs when the options differ" do
    a = UrlCache.new("https://example.com", {accept: "text/html"})
    b = UrlCache.new("https://example.com", {accept: "application/json"})
    refute_equal a.cache_key, b.cache_key
  end

  test "cache_key starts with the url_cache_ prefix" do
    cache = UrlCache.new("https://example.com")
    assert_match(/\Aurl_cache_[0-9a-f]+\z/, cache.cache_key)
  end

  test "body returns the cached response body" do
    cache = UrlCache.new("https://example.com/foo")
    Rails.cache.write(cache.cache_key, ["hello body", {"content-type" => "text/html"}])

    assert_equal "hello body", cache.body
  end

  test "headers returns the cached response headers" do
    cache = UrlCache.new("https://example.com/foo")
    Rails.cache.write(cache.cache_key, ["hello body", {"content-type" => "text/html"}])

    assert_equal({"content-type" => "text/html"}, cache.headers)
  end

  test "a failed response is not cached, so a later success is returned" do
    url = "http://example.com/oembed-#{SecureRandom.hex(6)}"

    stub_request(:get, url).to_return(status: 503, body: "<html>503 Service Unavailable</html>")
    UrlCache.new(url).body

    stub_request(:get, url).to_return(status: 200, body: "the real page")
    assert_equal "the real page", UrlCache.new(url).body
  end

  test "body is nil when the response failed" do
    url = "http://example.com/oembed-#{SecureRandom.hex(6)}"
    stub_request(:get, url).to_return(status: 404, body: "not found")

    assert_nil UrlCache.new(url).body
  end

  test "a successful response is cached" do
    url = "http://example.com/oembed-#{SecureRandom.hex(6)}"
    stub_request(:get, url).to_return(status: 200, body: "the real page")

    assert_equal "the real page", UrlCache.new(url).body

    stub_request(:get, url).to_return(status: 200, body: "a different page")
    assert_equal "the real page", UrlCache.new(url).body
  end
end
