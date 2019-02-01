require "test_helper"

class SavePagesTest < ActiveSupport::TestCase
  setup do
    user = users(:ben)
    @entry = create_tweet_entry(user.feeds.first)
  end

  test "should build" do
    article_url = "https://9to5mac.com/2018/01/12/final-cut-pro-x-how-to-improve-slow-motion-in-your-projects-video/"
    url = "https://mercury.postlight.com/parser?url=#{article_url}"
    stub_request_file("parsed_page.json", url, headers: {"Content-Type" => "application/json; charset=utf-8"})

    SavePages.new.perform(@entry.id)

    saved_pages = @entry.reload.data["saved_pages"]
    assert saved_pages.key?(article_url), "Entry should have saved page"
    page = saved_pages[article_url]["result"]

    %w[title author url date_published content domain].each do |key|
      assert page.key?(key), "page is missing #{key}"
    end
  end
end
