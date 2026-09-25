require "test_helper"

class RemoteFileTest < ActiveSupport::TestCase
  # Until RemoteFile goes, its camo_url is Camo's.
  test "camo_url delegates to Camo" do
    url = "http://example.com/image.jpg"
    assert_equal Camo.url(url), RemoteFile.camo_url(url)
  end

  # Readers still calling signed_url get the same URL as TwitterAvatar's.
  test "signed_url delegates to TwitterAvatar.path" do
    url = "https://pbs.twimg.com/profile_images/1/a.png"
    assert_equal TwitterAvatar.path(url), RemoteFile.signed_url(url)
  end
end
