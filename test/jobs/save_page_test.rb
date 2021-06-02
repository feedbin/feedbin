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
end
