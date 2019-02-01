require "test_helper"

class ViewLinkCacheTest < ActiveSupport::TestCase
  test "should cache link" do
    url = SecureRandom.hex
    stub_request_file("parsed_page.json", "https://mercury.postlight.com/parser?url=#{url}", headers: {"Content-Type" => "application/json; charset=utf-8"})
    ViewLinkCache.new.perform(url)

    key = FeedbinUtils.page_cache_key(url)
    result = Rails.cache.fetch(key)
    assert_instance_of MercuryParser, result
  end

  test "should not cache link" do
    url = SecureRandom.hex
    stub_request_file("parsed_page.json", "https://mercury.postlight.com/parser?url=#{url}", headers: {"Content-Type" => "application/json; charset=utf-8"})
    ViewLinkCache.new.perform(url, Time.now)

    key = FeedbinUtils.page_cache_key(url)
    result = Rails.cache.fetch(key)
    assert_nil result
  end
end
