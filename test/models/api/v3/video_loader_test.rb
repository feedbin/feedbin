require "test_helper"

class Api::V3::VideoLoaderTest < ActiveSupport::TestCase
  setup do
    @feed = Feed.create!(feed_url: "https://example.com/feed")
  end

  test "video_ids reads iframed YouTube videos in order, once each" do
    html = <<~HTML
      <iframe src="https://www.youtube.com/embed/AAA"></iframe><p>x</p>
      <iframe width="560" src="https://www.youtube-nocookie.com/embed/BBB?start=30&amp;rel=0"></iframe>
      <iframe src="https://www.youtube.com/embed/AAA"></iframe>
      <iframe src='https://www.youtube.com/shorts/CCC'></iframe>
      <iframe src="https://player.vimeo.com/video/1"></iframe>
      <a href="https://www.youtube.com/watch?v=DDD">x</a>
    HTML

    assert_equal %w[AAA BBB CCC], Api::V3::VideoLoader.video_ids(html)
  end

  test "video_ids of nothing" do
    assert_equal [], Api::V3::VideoLoader.video_ids(nil)
    assert_equal [], Api::V3::VideoLoader.video_ids("<p>No video</p>")
  end

  test "call maps every entry to its harvested videos" do
    harvested = Embed.create!(source: :youtube_video, provider_id: "AAA", parent_id: "UC1", data: {"snippet" => {"title" => "A"}})
    with_videos = entry_with(%(<iframe src="https://www.youtube.com/embed/AAA"></iframe><iframe src="https://www.youtube.com/embed/ZZZ"></iframe>))
    without = entry_with("<p>Words</p>")

    result = Api::V3::VideoLoader.call(load(with_videos, without))

    assert_equal({with_videos.id => [Api::V3::VideoSerializer.new(harvested).to_h], without.id => []}, result)
  end

  test "call loads a page of entries in three queries" do
    Embed.create!(source: :youtube_video, provider_id: "AAA", parent_id: "UC1", data: {})
    Embed.create!(source: :youtube_video, provider_id: "BBB", parent_id: "UC2", data: {})
    Embed.create!(source: :youtube_channel, provider_id: "UC1", data: {})
    Embed.create!(source: :youtube_channel, provider_id: "UC2", data: {})
    create_image_row(provider: :embed_icon, provider_id: "UC1", kind: :avatar)
    entries = load(
      entry_with(%(<iframe src="https://www.youtube.com/embed/AAA"></iframe>)),
      entry_with(%(<iframe src="https://www.youtube.com/embed/BBB"></iframe>)),
      entry_with(%(<iframe src="https://www.youtube.com/embed/AAA"></iframe>))
    )

    result = assert_queries_count(3) { Api::V3::VideoLoader.call(entries) }

    assert_equal [["UC1", true], ["UC2", false], ["UC1", true]], entries.map { result[it.id].first[:channel].then { [it[:id], it[:icon].present?] } }
  end

  private

  def entry_with(content)
    create_entry(@feed).tap { it.update!(content: content) }
  end

  # As served: renderings stored and loaded, so the loader's queries are its own.
  def load(*entries)
    Entry.where(id: entries.map(&:id)).for_api_v3.to_a.each(&:rendering).sort_by { entries.map(&:id).index(it.id) }
  end
end
