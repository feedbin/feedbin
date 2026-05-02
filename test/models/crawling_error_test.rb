require "test_helper"

class CrawlingErrorTest < ActiveSupport::TestCase
  test "message returns the friendly text for known error codes" do
    assert_equal "Invalid URL",        CrawlingError.message("Addressable::URI::InvalidURIError")
    assert_equal "Connection error",   CrawlingError.message("Feedkit::ClientError")
    assert_equal "Not found",          CrawlingError.message("Feedkit::NotFound")
    assert_equal "Server error",       CrawlingError.message("Feedkit::ServerError")
    assert_equal "Connection timed out", CrawlingError.message("Feedkit::TimeoutError")
    assert_equal "Unauthorized",       CrawlingError.message("Feedkit::Unauthorized")
  end

  test "message falls back to 'Connection error' for unknown codes" do
    assert_equal "Connection error", CrawlingError.message("SomeOther::Error")
    assert_equal "Connection error", CrawlingError.message(nil)
  end
end
