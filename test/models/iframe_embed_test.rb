require "test_helper"

class IframeEmbedTest < ActiveSupport::TestCase
  test "initialize forces the scheme to https" do
    embed = IframeEmbed.new("http://example.com/video")
    assert_equal "https", embed.embed_url.scheme
  end

  test "title, subtitle, canonical_url, image_url, type return nil when there is no data" do
    embed = IframeEmbed.new("https://example.com/video")
    assert_nil embed.title
    assert_nil embed.subtitle
    assert_nil embed.image_url
    assert_nil embed.type
    assert_equal "https://example.com/video", embed.canonical_url
  end

  test "cache_key is deterministic for the same url" do
    a = IframeEmbed.new("https://example.com/video")
    b = IframeEmbed.new("https://example.com/video")
    assert_equal a.cache_key, b.cache_key
  end

  test "cache_key is prefixed with iframe_embed_" do
    embed = IframeEmbed.new("https://example.com/video")
    assert_match(/\Aiframe_embed_[0-9a-f]+\z/, embed.cache_key)
  end

  test "iframe_src merges in query params from iframe_params" do
    embed = IframeEmbed.new("https://example.com/video?foo=1")
    assert_equal "https://example.com/video?foo=1", embed.iframe_src
  end

  test "clean_name returns the lowercased class name" do
    assert_equal "iframeembed", IframeEmbed.new("https://example.com/video").clean_name
  end

  test "youtube? defaults to false" do
    refute_predicate IframeEmbed.new("https://example.com/video"), :youtube?
  end

  test "recognize_url? returns false when no patterns match" do
    refute IframeEmbed.recognize_url?("https://example.com/anything")
  end

  test "normalize_url unwraps embedly src URLs" do
    inner = "https://www.youtube.com/embed/abc123"
    embedly = "https://cdn.embedly.com/widgets/media.html?src=#{CGI.escape(inner)}"
    assert_equal inner, IframeEmbed.normalize_url(embedly)
  end

  test "normalize_url returns non-embedly urls unchanged" do
    url = "https://example.com/foo?bar=baz"
    assert_equal url, IframeEmbed.normalize_url(url)
  end

  test "find_embed_source falls back to Default for an unknown url" do
    assert_equal IframeEmbed::Default, IframeEmbed.find_embed_source("https://example.com/anything")
  end
end
