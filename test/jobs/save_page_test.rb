require "test_helper"

class SavePageTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @user = users(:ben)
  end

  test "should create page" do
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    url = "http://example.com/saved_page"
    Sidekiq::Worker.clear_all
    assert_difference "Feed.count", +1 do
      assert_difference "Entry.count", +1 do
        SavePage.new.perform(@user.id, url, "Title")
      end
    end
    entry = Entry.find_by_url url
  end

  test "should save tweet" do
    tweet_entry = create_tweet_entry(@user.feeds.first)
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    url = "https://twitter.com/JeffBenjam/status/952239648633491457"
    SavePage.new.perform(@user.id, url, "Title")
    entry = @user.feeds.pages.first.entries.first
    assert entry.tweet?
  end

  test "should raise MissingPage error and enqueue retry" do
    stub_request(:get, /extract\.example\.com/).to_return(status: 500)
    url = "http://example.com/saved_page"
    assert_raises(SavePage::MissingPage) do
      SavePage.new.perform(@user.id, url, "Title")
    end
  end

  test "should save YouTube video" do
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    youtube_video_id = "video_id"
    videos = {
      items: [
        {
          id: youtube_video_id,
          snippet: {title: "Title", description: "Description", channelTitle: "Author"}
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/videos})
      .to_return body: videos.to_json, headers: {content_type: "application/json"}

    stub_request(:get, %r{www.googleapis.com/youtube/v3/channels})
      .to_return body: { items: [ { id: "channel_id" } ] }.to_json, headers: {content_type: "application/json"}


    url = "https://www.youtube.com/watch?v=#{youtube_video_id}"
    assert_difference "Entry.count", +1 do
      SavePage.new.perform(@user.id, url, nil)
    end
    entry = Entry.find_by_url url
    assert_equal "Title", entry.title
    assert_equal "Description", entry.content
    assert_equal "Author", entry.author
  end
end
