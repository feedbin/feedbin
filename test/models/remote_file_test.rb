require "test_helper"

class RemoteFileTest < ActiveSupport::TestCase
  # Until RemoteFile goes, its camo_url is Camo's.
  test "camo_url delegates to Camo" do
    url = "http://example.com/image.jpg"
    assert_equal Camo.url(url), RemoteFile.camo_url(url)
  end
end
