require "test_helper"

class HarvestLinksTest < ActiveSupport::TestCase
  setup do
    user = users(:ben)
    @entry = create_tweet_entry(user.feeds.first)
  end

  test "should build" do
    article_url = "https://9to5mac.com/2018/01/12/final-cut-pro-x-how-to-improve-slow-motion-in-your-projects-video/"
    url = "https://extract.example.com/parser/user/4e4143c7bd4d8c935741d37a3c14f61a268a5b79?base64_url=aHR0cHM6Ly85dG81bWFjLmNvbS8yMDE4LzAxLzEyL2ZpbmFsLWN1dC1wcm8teC1ob3ctdG8taW1wcm92ZS1zbG93LW1vdGlvbi1pbi15b3VyLXByb2plY3RzLXZpZGVvLw=="
    stub_request_file("parsed_page.json", url, headers: {"Content-Type" => "application/json; charset=utf-8"})

    HarvestLinks.new.perform(@entry.id)

    saved_pages = @entry.reload.data["saved_pages"]
    assert saved_pages.key?(article_url), "Entry should have saved page"
    page = saved_pages[article_url]["result"]

    %w[title author url date_published content domain].each do |key|
      assert page.key?(key), "page is missing #{key}"
    end
  end
end
