require "test_helper"

class ConditionalHttpTest < ActiveSupport::TestCase
  test "should get http headers with date" do
    last_modified = Time.now
    etag = SecureRandom.hex
    expected = {
      "If-None-Match" => etag,
      "If-Modified-Since" => last_modified.httpdate,
    }
    assert_equal expected, ConditionalHTTP.new(etag, last_modified).to_h
  end

  test "should get http headers with string" do
    last_modified = "Tue, 16 Aug 2016 05:07:33 GMT"
    etag = SecureRandom.hex
    expected = {
      "If-None-Match" => etag,
      "If-Modified-Since" => last_modified,
    }
    assert_equal expected, ConditionalHTTP.new(etag, last_modified).to_h
  end
end
