require "test_helper"

class HarvestLinksTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
  end

  test "should find tweet links" do
    entry = create_tweet_entry(@user.feeds.first)

    article_url = "https://9to5mac.com/2018/01/12/final-cut-pro-x-how-to-improve-slow-motion-in-your-projects-video/"
    url = "https://extract.example.com/parser/user/4e4143c7bd4d8c935741d37a3c14f61a268a5b79?base64_url=aHR0cHM6Ly85dG81bWFjLmNvbS8yMDE4LzAxLzEyL2ZpbmFsLWN1dC1wcm8teC1ob3ctdG8taW1wcm92ZS1zbG93LW1vdGlvbi1pbi15b3VyLXByb2plY3RzLXZpZGVvLw=="
    stub_request_file("parsed_page.json", url, headers: {"Content-Type" => "application/json; charset=utf-8"})

    HarvestLinks.new.perform(entry.id)

    saved_pages = entry.reload.data["saved_pages"]
    assert saved_pages.key?(article_url), "Entry should have saved page"
    page = saved_pages[article_url]["result"]

    %w[title author url date_published content domain].each do |key|
      assert page.key?(key), "page is missing #{key}"
    end
  end

  test "should find micropost links" do
    xml = File.read(support_file("microposts.xml"))
    parsed = Feedkit::Parser::XMLFeed.new(xml, "http://example.com")
    feed = Feed.create_from_parsed_feed(parsed)
    entry = feed.entries.first

    article_url = "https://chriscoyier.net/2022/12/14/behooves/"
    url = "https://extract.example.com/parser/user/33177dd530b122f53cc426423d4155dc70345319?base64_url=aHR0cHM6Ly9jaHJpc2NveWllci5uZXQvMjAyMi8xMi8xNC9iZWhvb3Zlcy8="
    stub_request_file("parsed_page.json", url, headers: {"Content-Type" => "application/json; charset=utf-8"})

    HarvestLinks.new.perform(entry.id)

    saved_pages = entry.reload.data["saved_pages"]
    assert saved_pages.key?(article_url), "Entry should have saved page"
    page = saved_pages[article_url]["result"]

    %w[title author url date_published content domain].each do |key|
      assert page.key?(key), "page is missing #{key}"
    end
  end

  test "should ignore links to itself" do
    xml = File.read(support_file("microposts.xml"))
    parsed = Feedkit::Parser::XMLFeed.new(xml, "http://example.com")
    feed = Feed.create_from_parsed_feed(parsed)

    host = "chriscoyier.net"

    entry = feed.entries.first
    entry.update(url: "http://#{host}/example")

    # if hostname filter is not present, this will raise an error when it tries to download the url
    HarvestLinks.new.perform(entry.id)
  end
end
