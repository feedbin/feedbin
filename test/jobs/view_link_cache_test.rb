require "test_helper"

class ViewLinkCacheTest < ActiveSupport::TestCase
  test "calls MercuryParser.parse for the url when expires_at is nil" do
    called_with = nil
    MercuryParser.stub :parse, ->(url) { called_with = url; OpenStruct.new(content: "x") } do
      ViewLinkCache.new.perform("https://example.com/foo")
    end
    assert_equal "https://example.com/foo", called_with
  end

  test "calls MercuryParser.parse when expires_at is in the future" do
    called = false
    MercuryParser.stub :parse, ->(_) { called = true; OpenStruct.new(content: "x") } do
      ViewLinkCache.new.perform("https://example.com/foo", 1.hour.from_now.to_i)
    end
    assert called
  end

  test "skips MercuryParser when expires_at has already passed" do
    called = false
    MercuryParser.stub :parse, ->(_) { called = true; OpenStruct.new(content: "x") } do
      ViewLinkCache.new.perform("https://example.com/foo", 1.hour.ago.to_i)
    end
    refute called
  end

  test "rescues HTTP::TimeoutError and returns truthy" do
    MercuryParser.stub :parse, ->(_) { raise HTTP::TimeoutError, "timeout" } do
      assert_equal true, ViewLinkCache.new.perform("https://example.com/foo")
    end
  end

  test "rescues HTTP::ConnectionError and returns truthy" do
    MercuryParser.stub :parse, ->(_) { raise HTTP::ConnectionError, "conn" } do
      assert_equal true, ViewLinkCache.new.perform("https://example.com/foo")
    end
  end
end
