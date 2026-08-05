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

  test "should create page with html" do
    stub_request_file("parsed_page.json", /extract\.example\.com/, {headers: {"Content-Type" => "application/json; charset=utf-8"}}, :post)
    url = "http://example.com/saved_page"
    Sidekiq::Worker.clear_all
    file = Tempfile.new
    file.close
    assert_difference "Feed.count", +1 do
      assert_difference "Entry.count", +1 do
        SavePage.new.perform(@user.id, url, "Title", file.path)
      end
    end
    file.unlink
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

  test "a retry of an unparseable page leaves the entry where it was in the Pages list" do
    stub_request(:get, /extract\.example\.com/).to_return(status: 500)
    url = "http://example.com/saved_page"

    entry = assert_raises(SavePage::MissingPage) {
      SavePage.new.perform(@user.id, url, "Title")
    }.entry
    published = entry.reload.published

    travel_to 6.hours.from_now do
      assert_raises(SavePage::MissingPage) do
        SavePage.new.perform(@user.id, url, "Title")
      end
    end

    assert_equal published.to_i, entry.reload.published.to_i,
      "re-dating the entry floats an unreadable page back to the top of Pages on every retry"
  end

  test "a retry of an unparseable page does not re-enqueue its side-effect jobs" do
    stub_request(:get, /extract\.example\.com/).to_return(status: 500)
    url = "http://example.com/saved_page"

    assert_raises(SavePage::MissingPage) do
      SavePage.new.perform(@user.id, url, "Title")
    end
    images = ImageSaver.jobs.count
    favicons = FaviconCrawler::Finder.jobs.count

    assert_raises(SavePage::MissingPage) do
      SavePage.new.perform(@user.id, url, "Title")
    end

    assert_equal images, ImageSaver.jobs.count
    assert_equal favicons, FaviconCrawler::Finder.jobs.count
  end

  test "should save YouTube video" do
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    youtube_video_id = "video_id"
    videos = {
      items: [
        {
          id: youtube_video_id,
          snippet: {title: "Title", description: "Description", channelTitle: "Author", channelId: "channel_id"}
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
