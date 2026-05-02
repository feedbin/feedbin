require "test_helper"

class IframeEmbed::TwitterTest < ActiveSupport::TestCase
  def oembed_payload
    {
      "author_name" => "Alice",
      "author_url" => "https://twitter.com/alice",
      "url" => "https://twitter.com/alice/status/12345",
      "html" => %(<blockquote><p>Hello <a href="pic.twitter.com/abc">pic.twitter.com/abc</a></p><a href="https://twitter.com/alice/status/12345">2024-01-15T12:00:00Z</a></blockquote>)
    }
  end

  def stub_url_cache(map)
    UrlCache.stub :new, ->(url, _ = {}) {
      response = Object.new
      body = map.fetch(url) { map[:default] }
      response.define_singleton_method(:body) { body }
      response
    } do
      yield
    end
  end

  test "name returns author_name from the oembed payload" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      assert_equal "Alice", embed.name
    end
  end

  test "screen_name prefixes the user with @" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      assert_equal "@alice", embed.screen_name
    end
  end

  test "permalink reads url from the oembed payload" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      assert_equal "https://twitter.com/alice/status/12345", embed.permalink
    end
  end

  test "author_url reads author_url from the oembed payload" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      assert_equal "https://twitter.com/alice", embed.author_url
    end
  end

  test "date parses the date in the linked anchor" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      result = embed.date
      assert_kind_of Time, result
      assert_equal 2024, result.year
    end
  end

  test "content returns the inner <p> as a string" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      assert_includes embed.content, "<p>"
      assert_includes embed.content, "Hello"
    end
  end

  test "profile_image_url returns the TwitterUser image when known" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    fake_user = Object.new
    fake_user.define_singleton_method(:profile_image) { "https://pic/alice.png" }
    fake_relation = Object.new
    fake_relation.define_singleton_method(:take) { fake_user }
    TwitterUser.stub :where_lower, ->(*) { fake_relation } do
      stub_url_cache(default: JSON.dump(oembed_payload)) do
        assert_equal "https://pic/alice.png", embed.profile_image_url
      end
    end
  end

  test "profile_image_url falls back to the default favicon when user is unknown" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/unknownuser/status/9999")
    payload = oembed_payload.merge("author_url" => "https://twitter.com/unknownuser")
    stub_url_cache(default: JSON.dump(payload)) do
      assert_includes embed.profile_image_url, "favicon-profile-default"
    end
  end

  test "image_url extracts og:image from the picture page when present" do
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    pic_html = '<html><head><meta property="og:image" content="https://img.test/p.jpg"></head></html>'
    UrlCache.stub :new, ->(url, _ = {}) {
      body = url == "https://publish.twitter.com/oembed" ? JSON.dump(oembed_payload) : pic_html
      Class.new {
        define_method(:body) { body }
      }.new
    } do
      assert_equal "https://img.test/p.jpg", embed.image_url
    end
  end

  test "image_url returns nil when there are no pic.twitter.com links" do
    payload = oembed_payload.merge("html" => "<blockquote><p>plain</p><a>2024-01-01</a></blockquote>")
    embed = IframeEmbed::Twitter.new("https://twitter.com/alice/status/12345")
    stub_url_cache(default: JSON.dump(payload)) do
      assert_nil embed.image_url
    end
  end

  test "download fetches the oembed payload eagerly via name" do
    embed = nil
    stub_url_cache(default: JSON.dump(oembed_payload)) do
      embed = IframeEmbed::Twitter.download("https://twitter.com/alice/status/12345")
    end
    assert_kind_of IframeEmbed::Twitter, embed
  end
end
