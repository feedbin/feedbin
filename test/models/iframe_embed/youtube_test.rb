require "test_helper"

class IframeEmbed::YoutubeTest < ActiveSupport::TestCase
  setup do
    @url = "https://www.youtube.com/watch?v=ABC123"
  end

  test "supported_urls returns the application config" do
    assert_equal Feedbin::Application.config.youtube_embed_urls, IframeEmbed::Youtube.supported_urls
  end

  test "oembed_url is the YouTube oembed endpoint" do
    embed = IframeEmbed::Youtube.new(@url)
    assert_equal "https://www.youtube.com/oembed", embed.oembed_url
  end

  test "iframe_params include autoplay and enablejsapi" do
    embed = IframeEmbed::Youtube.new(@url)
    params = embed.iframe_params
    assert_equal "1", params[:autoplay]
    assert_equal "1", params[:enablejsapi]
  end

  test "oembed_params returns the canonical_url + format" do
    embed = IframeEmbed::Youtube.new(@url)
    params = embed.oembed_params
    assert_equal "json", params[:format]
    assert_equal embed.canonical_url, params[:url]
  end

  test "canonical_url uses the youtu.be short form with the provider_id" do
    embed = IframeEmbed::Youtube.new(@url)
    assert_match %r{^https://youtu\.be/}, embed.canonical_url
  end

  test "youtube? is always true" do
    assert IframeEmbed::Youtube.new(@url).youtube?
  end

  test "image_url uses maxresdefault when HEAD returns 200, otherwise the original thumbnail" do
    embed = IframeEmbed::Youtube.new(@url)
    embed.stub :data, {"thumbnail_url" => "https://i.ytimg.com/vi/ABC/hqdefault.jpg"} do
      Rails.cache.stub :fetch, ->(_key, &block) { 200 } do
        assert_match %r{maxresdefault}, embed.image_url
      end
      Rails.cache.stub :fetch, ->(_key, &block) { 404 } do
        assert_match %r{hqdefault}, embed.image_url
      end
    end
  end

  test "channel_name and profile_image are falsy when there is no Embed record" do
    embed = IframeEmbed::Youtube.new(@url)
    refute embed.channel_name
    refute embed.profile_image
  end

  test "duration is nil when no Embed record exists" do
    embed = IframeEmbed::Youtube.new(@url)
    assert_nil embed.duration
  end

  test "cache_key falls back to the Iframe::Embed default when there is no video" do
    embed = IframeEmbed::Youtube.new(@url)
    assert_match(/iframe_embed_/, embed.cache_key)
  end

  test "chapters is falsy when there is no Embed record" do
    embed = IframeEmbed::Youtube.new(@url)
    refute embed.chapters
  end
end
