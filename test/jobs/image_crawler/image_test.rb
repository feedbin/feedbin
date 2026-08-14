require "test_helper"

module ImageCrawler
  class ImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    test "ignores unknown attributes" do
      image = Image.new("id" => "abc", "attribute_from_the_future" => "value")
      assert_equal "abc", image.id
    end

    test "sets known attributes" do
      image = Image.new("id" => "abc", "preset_name" => "primary", "image_urls" => ["http://example.com/a.jpg"])
      assert_equal "primary", image.preset_name
      assert_equal ["http://example.com/a.jpg"], image.image_urls
    end

    test "unified? requires an opted-in preset and the R2 bucket env" do
      image = Image.new_with_attributes(id: "a", preset_name: "primary", image_urls: [], provider: 2, provider_id: 1)
      refute image.unified?

      with_env("R2_BUCKET_IMAGES" => "images-test") do
        assert image.unified?
        icon = Image.new_with_attributes(id: "a", preset_name: "icon", image_urls: [], provider: ::Image.providers[:remote_file], provider_id: 1)
        refute icon.unified?
      end
    end

    test "storage_path is derived from original_url" do
      image = Image.new_with_attributes(id: "a", preset_name: "primary", image_urls: [], provider: 2, provider_id: 1, original_url: "http://example.com/a.jpg")
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304"), image.storage_path
    end

    test "send_to_feedbin includes unified metadata when unified" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        image = Image.new_with_attributes(
          id: "a", preset_name: "primary", image_urls: [],
          provider: ::Image.providers[:entry_preview], provider_id: 1,
          original_url: "http://example.com/a.jpg", final_url: "http://example.com/a.jpg",
          storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
          width: 542, height: 304, bytesize: 9_999, placeholder_color: "aabbcc"
        )
        image.send_to_feedbin

        _, payload = EntryImage.jobs.last["args"]
        assert_equal image.storage_path, payload["storage_path"]
        assert_equal 9_999,              payload["bytesize"]
        assert_equal "entry_preview",    payload["provider"]
      end
    end

    test "send_to_feedbin keeps the legacy payload shape when not unified" do
      image = Image.new_with_attributes(
        id: "a", preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg", final_url: "http://example.com/a.jpg",
        storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
        width: 542, height: 304, placeholder_color: "aabbcc"
      )
      image.send_to_feedbin

      _, payload = EntryImage.jobs.last["args"]
      refute payload.key?("storage_path")
    end

    test "create_image records a usage row" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        image = Image.new_with_attributes(
          id: "a", preset_name: "primary", image_urls: [],
          provider: ::Image.providers[:entry_preview], provider_id: 42, feed_id: 7,
          original_url: "http://example.com/a.jpg", final_url: "http://example.com/a-final.jpg",
          storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
          width: 542, height: 304, bytesize: 9_999, placeholder_color: "aabbcc",
          fingerprint: SecureRandom.hex(16)
        )

        record = image.create_image

        assert_equal "42", record.provider_id
        assert_equal 7, record.feed_id
        assert_equal image.storage_path, record.storage_path
        assert_equal 9_999, record.bytesize
        assert_equal "https://s3.amazonaws.com/bucket/a/abc.jpg", record.data["legacy_storage_url"]
        assert_equal "primary", record.data["preset"]
        assert_equal "http://example.com/a-final.jpg", record.data["final_url"]
      end
    end

    test "storage_path and content type follow the preset format" do
      image = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg"
      )
      assert_equal "webp", image.preset.format
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304", "webp"), image.storage_path
      assert_equal "image/webp", image.r2_storage_options["Content-Type"]
    end

    # variant names the rendering recipe, not the result. A 180x180 touch icon
    # rendered by the 200x200 limit recipe stays 180x180 and is still variant
    # "200x200" -- keying on the actual output would fragment the namespace and
    # break dedup between two renditions of the same recipe.
    test "icon presets keep their recipe as the variant and store png" do
      %w[favicon touch_icon].zip(["32x32", "200x200"]).each do |preset_name, variant|
        image = Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: preset_name, image_urls: [],
          provider: ::Image.providers[:feed_icon], provider_id: 1,
          original_url: "http://example.com/favicon.ico",
          width: 17, height: 17
        )
        assert_equal variant, image.variant
        assert_equal "png", image.preset.format
        assert_equal "image/png", image.r2_storage_options["Content-Type"]
        assert_equal :icon_crop, image.preset.crop
      end
    end

    # Icons mutate under a stable URL, so the URL cannot name the object. Two
    # different sources that happen to serve identical bytes get one object;
    # one URL serving new bytes gets a new one.
    test "icon presets derive storage_path from the original bytes" do
      fingerprint = Digest::MD5.hexdigest("bytes")
      build = ->(url) {
        Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
          provider: ::Image.providers[:feed_icon], provider_id: 1,
          original_url: url, original_fingerprint: fingerprint
        )
      }

      assert build.call("http://a.example.com/favicon.ico").content_addressed?
      assert_equal ::Image.content_storage_path_for(fingerprint, "32x32", "png"),
        build.call("http://a.example.com/favicon.ico").storage_path
      assert_equal build.call("http://a.example.com/favicon.ico").storage_path,
        build.call("http://b.example.com/favicon.ico").storage_path
      assert_not build.call("http://a.example.com/favicon.ico").legacy_store?
    end

    # A pre-migration Process (whose payload lacks original_fingerprint) can
    # hand off to a post-migration Upload on the same host, since Process and
    # Upload are host-local and retry: false. Silently hashing a blank
    # fingerprint would collapse every such image onto one shared path instead
    # of surfacing the mismatch.
    test "storage_path raises for a content-addressed preset with no original_fingerprint" do
      image = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
        provider: ::Image.providers[:feed_icon], provider_id: 1,
        original_url: "http://example.com/favicon.ico"
      )

      assert image.content_addressed?
      assert_raises(ArgumentError) { image.storage_path }
    end

    test "entry presets stay keyed by url" do
      image = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg", original_fingerprint: Digest::MD5.hexdigest("bytes")
      )

      assert_not image.content_addressed?
      assert image.legacy_store?
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304", "webp"), image.storage_path
    end

    test "create_image sweeps the object it replaced, and only when it changed" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        build = ->(fingerprint) {
          Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
            provider: ::Image.providers[:feed_icon], provider_id: 7,
            original_url: "http://example.com/favicon.ico",
            original_fingerprint: fingerprint,
            fingerprint: SecureRandom.hex(16),
            width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc"
          )
        }

        first = build.call(Digest::MD5.hexdigest("old bytes"))
        assert_no_difference -> { ImageReplacementCollector.jobs.size } do
          first.create_image
        end

        assert_no_difference -> { ImageReplacementCollector.jobs.size } do
          build.call(Digest::MD5.hexdigest("old bytes")).create_image
        end

        assert_difference -> { ImageReplacementCollector.jobs.size }, +1 do
          build.call(Digest::MD5.hexdigest("new bytes")).create_image
        end

        assert_equal [[first.storage_path]], ImageReplacementCollector.jobs.last["args"]
      end
    end

    # One object per show instead of one per episode: a show and every episode
    # reusing the same artwork fingerprint to the same storage_path, across
    # both presets, because they share a variant and a format.
    test "podcast presets are content-addressed and share objects across show and episode" do
      fingerprint = Digest::MD5.hexdigest("cover bytes")
      build = ->(preset, provider, url) {
        Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: preset, image_urls: [],
          provider: ::Image.providers[provider], provider_id: 1,
          original_url: url, original_fingerprint: fingerprint
        )
      }

      episode = build.call("podcast", :entry_icon, "http://example.com/ep1.jpg")
      show = build.call("podcast_feed", :feed_icon, "http://example.com/show.jpg")

      assert episode.content_addressed?
      assert episode.legacy_store?, "the legacy S3 object is still the fallback read path"
      assert_equal "200x200", episode.variant
      assert_equal "jpg", episode.preset.format
      assert_equal :fill_crop, episode.preset.crop
      assert_equal ::Image.content_storage_path_for(fingerprint, "200x200", "jpg"), episode.storage_path
      assert_equal episode.storage_path, show.storage_path
    end

    # touch_icon is also 200x200 but renders png through a different recipe.
    # The extension is what keeps the two object keys apart.
    test "podcast artwork does not collide with touch_icon at the same variant" do
      fingerprint = Digest::MD5.hexdigest("cover bytes")
      podcast = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "podcast", image_urls: [],
        provider: ::Image.providers[:entry_icon], provider_id: 1,
        original_url: "http://example.com/a.jpg", original_fingerprint: fingerprint
      )
      touch = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "touch_icon", image_urls: [],
        provider: ::Image.providers[:feed_icon], provider_id: 1,
        original_url: "http://example.com/a.jpg", original_fingerprint: fingerprint
      )

      assert_equal "200x200", touch.variant
      refute_equal podcast.storage_path, touch.storage_path
    end

    # Content-addressed and R2-only. Unlike podcast artwork there is no legacy
    # object to dual-write: the fallback read path is a third-party ggpht url
    # rendered through the signing proxy, which costs us no storage.
    test "channel_avatar is content-addressed, R2-only, and keyed by the bytes" do
      fingerprint = Digest::MD5.hexdigest("avatar bytes")
      image = Image.new_with_attributes(
        id: "UCabc-channel", preset_name: "channel_avatar", image_urls: [],
        provider: ::Image.providers[:embed_icon], provider_id: "UCabc",
        original_url: "https://yt3.ggpht.com/avatar.jpg", original_fingerprint: fingerprint
      )

      assert image.content_addressed?
      refute image.legacy_store?, "there is no legacy object for this tenant"
      assert_equal "200x200", image.variant
      assert_equal "png", image.preset.format
      assert_equal :limit_png, image.preset.crop
      assert_equal ::Image.content_storage_path_for(fingerprint, "200x200", "png"), image.storage_path
    end

    # Not a collision: the two presets render the same recipe at the same size
    # in the same format, so identical source bytes are meant to share one
    # stored object. cropper_test pins the recipes byte-for-byte.
    test "channel_avatar and touch_icon share an object for identical bytes" do
      fingerprint = Digest::MD5.hexdigest("avatar bytes")
      build = ->(preset, provider) {
        Image.new_with_attributes(
          id: "a", preset_name: preset, image_urls: [],
          provider: ::Image.providers[provider], provider_id: "UCabc",
          original_url: "https://yt3.ggpht.com/avatar.jpg", original_fingerprint: fingerprint
        )
      }

      assert_equal build.call("touch_icon", :feed_icon).storage_path,
        build.call("channel_avatar", :embed_icon).storage_path
    end

    # Same size, different format. podcast is jpg and the extension is the
    # only thing keeping the two object keys apart.
    test "channel_avatar does not collide with podcast at the same variant" do
      fingerprint = Digest::MD5.hexdigest("avatar bytes")
      avatar = Image.new_with_attributes(
        id: "a", preset_name: "channel_avatar", image_urls: [],
        provider: ::Image.providers[:embed_icon], provider_id: "UCabc",
        original_url: "https://example.com/a.jpg", original_fingerprint: fingerprint
      )
      podcast = Image.new_with_attributes(
        id: "b", preset_name: "podcast", image_urls: [],
        provider: ::Image.providers[:entry_icon], provider_id: 1,
        original_url: "https://example.com/a.jpg", original_fingerprint: fingerprint
      )

      refute_equal avatar.storage_path, podcast.storage_path
    end
  end
end
