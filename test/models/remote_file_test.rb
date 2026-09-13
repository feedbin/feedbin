require "test_helper"

class RemoteFileTest < ActiveSupport::TestCase
  test "camo_url builds on CAMO_HOST with CAMO_KEY by default" do
    url = "http://example.com/image.jpg"
    signature = OpenSSL::HMAC.hexdigest("sha1", RemoteFile.secret_key, url)
    hex = url.unpack1("H*")

    assert_equal "https://#{URI(ENV["CAMO_HOST"]).host}/#{signature}/#{hex}", RemoteFile.camo_url(url)
  end

  # An origin, scheme and port included, so a plain-http fleet and a
  # non-default port both work; a different key signs for that fleet.
  test "camo_url takes another origin and key" do
    url = "http://example.com/image.jpg"
    signature = OpenSSL::HMAC.hexdigest("sha1", "other-key", url)
    hex = url.unpack1("H*")

    assert_equal "http://146.190.44.162/#{signature}/#{hex}", RemoteFile.camo_url(url, host: "http://146.190.44.162", key: "other-key")
    assert_equal "https://camo.example.com:8443/#{signature}/#{hex}", RemoteFile.camo_url(url, host: "https://camo.example.com:8443", key: "other-key")
  end

  # The legacy icons bucket is public-read, so a crawler can hand the cached
  # object to Find as the candidate after the original url.
  test "legacy_object_url is the cached object for a url, or nil" do
    url = "https://example.com/avatar.png"
    RemoteFile.create!(fingerprint: RemoteFile.fingerprint(url), original_url: url, storage_url: "https://icons.example.net/abc/avatar.png")

    assert_equal "https://icons.example.net/abc/avatar.png", RemoteFile.legacy_object_url(url)
    assert_nil RemoteFile.legacy_object_url("https://example.com/other.png")
  end
end
