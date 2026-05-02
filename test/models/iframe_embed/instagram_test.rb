require "test_helper"

class IframeEmbed::InstagramTest < ActiveSupport::TestCase
  def stub_oembed(payload, &block)
    captured_url = nil
    fake_cache = Class.new do
      attr_reader :url, :options
      def initialize(url, options = {})
        @url = url
        @options = options
      end
      def body
        @body
      end
    end
    UrlCache.stub :new, ->(url, options = {}) {
      captured_url = url
      cache = fake_cache.new(url, options)
      cache.instance_variable_set(:@body, JSON.dump(payload))
      cache
    } do
      yield captured_url
    end
  end

  test "screen_name reads author_name from the oembed payload" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/ABC/")
    stub_oembed("author_name" => "alice", "thumbnail_url" => "x") do
      assert_equal "alice", embed.screen_name
    end
  end

  test "permalink builds an Instagram post URL from the URL shortcode" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/CODE/")
    assert_equal "https://www.instagram.com/p/CODE/", embed.permalink
  end

  test "permalink strips trailing path segments to recover the shortcode" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/CODE")
    assert_equal "https://www.instagram.com/p/CODE/", embed.permalink
  end

  test "author_url combines instagram domain with screen_name" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/ABC/")
    stub_oembed("author_name" => "alice", "thumbnail_url" => "x") do
      assert_equal "https://instagram.com/alice", embed.author_url
    end
  end

  test "media_url reads thumbnail_url from the oembed payload" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/ABC/")
    stub_oembed("author_name" => "alice", "thumbnail_url" => "https://thumb/img.jpg") do
      assert_equal "https://thumb/img.jpg", embed.media_url
    end
  end

  test "profile_image_url is always nil" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/ABC/")
    assert_nil embed.profile_image_url
  end

  test "data is fetched via UrlCache against the Instagram graph oembed endpoint" do
    embed = IframeEmbed::Instagram.new("https://www.instagram.com/p/ABC/")
    captured_url = nil
    captured_options = nil
    fake_cache = Object.new
    fake_cache.define_singleton_method(:body) { '{"author_name":"alice","thumbnail_url":"x"}' }
    UrlCache.stub :new, ->(url, options = {}) {
      captured_url = url
      captured_options = options
      fake_cache
    } do
      embed.screen_name
    end
    assert_equal "https://graph.facebook.com/v9.0/instagram_oembed", captured_url
    assert_equal "https://www.instagram.com/p/ABC/", captured_options[:params][:url]
    assert_equal "thumbnail_url,author_name", captured_options[:params][:fields]
  end

  test "download builds an instance and forces an oembed fetch" do
    fake_cache = Object.new
    fake_cache.define_singleton_method(:body) { '{"author_name":"alice","thumbnail_url":"x"}' }
    instance = nil
    UrlCache.stub :new, ->(*) { fake_cache } do
      instance = IframeEmbed::Instagram.download("https://www.instagram.com/p/ABC/")
    end
    assert_equal "alice", instance.screen_name
  end
end
