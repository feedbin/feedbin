require "test_helper"

class FeedOptionTest < ActiveSupport::TestCase
  test "stores the source it was constructed with" do
    option = FeedOption.new("https://example.com", "/feed.xml", "Title", "html_link")
    assert_equal "html_link", option.source
  end

  test "default source is 'unspecified'" do
    option = FeedOption.new("https://example.com", "/feed.xml")
    assert_equal "unspecified", option.source
  end

  test "href returns absolute http urls unchanged" do
    option = FeedOption.new("https://example.com", "https://other.example.com/feed.xml")
    assert_equal "https://other.example.com/feed.xml", option.href
  end

  test "href converts feed: scheme to http:" do
    option = FeedOption.new("https://example.com", "feed://example.com/feed.xml")
    assert_equal "http://example.com/feed.xml", option.href
  end

  test "href joins relative paths against base_url" do
    option = FeedOption.new("https://example.com/some/page", "feed.xml")
    assert_equal "https://example.com/some/feed.xml", option.href
  end

  test "href strips surrounding whitespace" do
    option = FeedOption.new("https://example.com", "  https://example.com/feed.xml  ")
    assert_equal "https://example.com/feed.xml", option.href
  end

  test "title strips RSS suffix" do
    option = FeedOption.new("https://example.com", "/feed", "Daring Fireball RSS")
    assert_equal "Daring Fireball", option.title
  end

  test "title strips Atom suffix" do
    option = FeedOption.new("https://example.com", "/feed", "Example Atom")
    assert_equal "Example", option.title
  end

  test "title falls back to href when title is missing" do
    option = FeedOption.new("https://example.com", "https://example.com/feed.xml", nil)
    assert_equal "https://example.com/feed.xml", option.title
  end
end
