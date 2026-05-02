require "test_helper"

class IframeEmbed::DefaultTest < ActiveSupport::TestCase
  test "fetch memoizes a UrlCache for the canonical URL" do
    embed = IframeEmbed::Default.new("https://example.com/video")
    fake_cache = Object.new
    fake_cache.define_singleton_method(:body) { "<html><head><title>Hello</title></head></html>" }
    UrlCache.stub :new, ->(_url) { fake_cache } do
      first = embed.fetch
      second = embed.fetch
      assert_same first, second
    end
  end

  test "title returns the document title when present" do
    embed = IframeEmbed::Default.new("https://example.com/video")
    fake_cache = Object.new
    fake_cache.define_singleton_method(:body) { "<html><head><title>Hello</title></head></html>" }
    UrlCache.stub :new, ->(_url) { fake_cache } do
      embed.fetch
      assert_equal "Hello", embed.title
    end
  end

  test "title falls back to 'Embed' when there is no title element" do
    embed = IframeEmbed::Default.new("https://example.com/video")
    fake_cache = Object.new
    fake_cache.define_singleton_method(:body) { "<html><head></head></html>" }
    UrlCache.stub :new, ->(_url) { fake_cache } do
      embed.fetch
      assert_equal "Embed", embed.title
    end
  end

  test "type is the demodulized class name" do
    embed = IframeEmbed::Default.new("https://example.com/video")
    assert_equal "default", embed.type
  end

  test "subtitle is the registrable host part" do
    embed = IframeEmbed::Default.new("https://media.example.co.uk/video")
    assert_equal "co.uk", embed.subtitle
  end

  test "image_url is always nil" do
    embed = IframeEmbed::Default.new("https://example.com/video")
    assert_nil embed.image_url
  end

  test "recognize_url? always returns true (the catch-all)" do
    assert IframeEmbed::Default.recognize_url?("https://anywhere")
  end
end
