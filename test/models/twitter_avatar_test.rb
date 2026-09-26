require "test_helper"

class TwitterAvatarTest < ActiveSupport::TestCase
  URL = "https://pbs.twimg.com/profile_images/659486593649012736/-TGFT8rs.png"

  # The copied rows are keyed by the MD5 of the URL, the key remote_files
  # used. Changing it would orphan every copied avatar.
  test "fingerprint is the MD5 of the url" do
    assert_equal Digest::MD5.hexdigest(URL), TwitterAvatar.fingerprint(URL)
  end

  # The icons path's existing URLs carry the signature the icon proxy made:
  # HMAC-SHA1 of the URL with the camo key. Changing it would break every
  # URL the CDN has cached.
  test "sign is the icon proxy's signature" do
    assert_equal OpenSSL::HMAC.hexdigest("sha1", Camo.secret_key, URL), TwitterAvatar.sign(URL)
  end

  test "a signature verifies for its decoded url and not for a changed one" do
    signature = TwitterAvatar.sign(URL)
    url = TwitterAvatar.decode(URL.unpack1("H*"))

    assert_equal URL, url
    assert TwitterAvatar.signature_valid?(signature, url)
    refute TwitterAvatar.signature_valid?(signature, "#{url}x")
    refute TwitterAvatar.signature_valid?(nil, url)
  end

  test "path is relative on the icons path without FILES_HOST" do
    with_env("FILES_HOST" => nil) do
      assert_equal "/files/icons/#{TwitterAvatar.sign(URL)}/#{URL.unpack1("H*")}", TwitterAvatar.path(URL)
    end
  end

  test "path is on FILES_HOST when it is set" do
    with_env("FILES_HOST" => "https://files.example.com") do
      assert_equal "https://files.example.com/files/icons/#{TwitterAvatar.sign(URL)}/#{URL.unpack1("H*")}", TwitterAvatar.path(URL)
    end
  end

  test "decode returns UTF-8" do
    assert_equal Encoding::UTF_8, TwitterAvatar.decode(URL.unpack1("H*")).encoding
  end

  test "resolve returns the stored copy's public url on a hit and nil on a miss" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      row = create_image_row(provider: :twitter_avatar, provider_id: TwitterAvatar.fingerprint(URL), feed_id: nil, kind: :avatar, url: URL, variant: "400x400")

      assert_equal "https://images.example.com/#{row.storage_path}", TwitterAvatar.resolve(URL)
      assert_nil TwitterAvatar.resolve("https://pbs.twimg.com/profile_images/1/other.png")
    end
  end
end
