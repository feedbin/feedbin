require 'test_helper'

class IframeEmbed::YoutubeTest < ActiveSupport::TestCase

  setup do
    @video_id = "9AxYQOX5_FM"
    url = "https://www.youtube.com/embed/#{@video_id}"
    stub_request_file("oembed.json", /www\.youtube\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    parser = IframeEmbed::Youtube.new(url)
    parser.fetch()
    @parser = parser
  end

  test "should recognize get video thumbnails" do
    assert_equal("https://i.ytimg.com/vi/#{@video_id}/maxresdefault.jpg", @parser.image_url)
    assert_equal("https://i.ytimg.com/vi/#{@video_id}/hqdefault.jpg", @parser.image_url_fallback)
  end

  test "should recognize get video data" do
    assert @parser.data.respond_to?(:has_key?)
  end

  test "should recognize youtube urls" do
    urls = %w[
      https://www.youtube.com/embed/9AxYQOX5_FM
      https://www.youtube-nocookie.com/embed/9AxYQOX5_FM
    ]
    urls.each do |url|
      assert IframeEmbed::Youtube.recognize_url?(url), "#{url} should be recognized"
      assert_equal "9AxYQOX5_FM", IframeEmbed::Youtube.new(url).video_id
    end
  end

end