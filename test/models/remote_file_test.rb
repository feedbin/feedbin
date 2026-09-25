require "test_helper"

class RemoteFileTest < ActiveSupport::TestCase
  test "camo_url builds on CAMO_HOST with CAMO_KEY by default" do
    url = "http://example.com/image.jpg"
    signature = OpenSSL::HMAC.hexdigest("sha1", RemoteFile.secret_key, url)
    hex = url.unpack1("H*")

    assert_equal "https://#{URI(ENV["CAMO_HOST"]).host}/#{signature}/#{hex}", RemoteFile.camo_url(url)
  end

  # CAMO_HOST is an origin, so its scheme and a non-default port carry over.
  test "camo_url keeps the scheme and port of CAMO_HOST" do
    url = "http://example.com/image.jpg"
    signature = OpenSSL::HMAC.hexdigest("sha1", RemoteFile.secret_key, url)
    hex = url.unpack1("H*")

    with_env("CAMO_HOST" => "http://camo.example.com:8443") do
      assert_equal "http://camo.example.com:8443/#{signature}/#{hex}", RemoteFile.camo_url(url)
    end
  end
end
