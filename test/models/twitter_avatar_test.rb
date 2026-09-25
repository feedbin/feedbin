require "test_helper"

class TwitterAvatarTest < ActiveSupport::TestCase
  URL = "https://pbs.twimg.com/profile_images/659486593649012736/-TGFT8rs.png"

  # The migrated rows are keyed by the value remote_files used, so the two
  # must agree while both exist.
  test "fingerprint matches RemoteFile.fingerprint" do
    assert_equal RemoteFile.fingerprint(URL), TwitterAvatar.fingerprint(URL)
  end

  # The icons path's existing URLs carry this signature, so it must match
  # what RemoteFile signed.
  test "sign matches the signature in RemoteFile.signed_url" do
    assert_equal RemoteFile.signed_url(URL).split("/")[-2], TwitterAvatar.sign(URL)
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
