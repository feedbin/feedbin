require "application_system_test_case"

class ArticleTest < ApplicationSystemTestCase
  test "Show article" do
    show_article
    assert_text @entries.first.content
  end

  test "Show tweet" do
    @user = users(:ben)
    @feed = create_feeds(@user, 1).first

    entry = create_tweet_entry(@user.feeds.first)

    login_as(@user)

    click_link(entry.tweet_summary)

    assert_selector ".tweet-text", text: entry.tweet_summary
  end

  test "star" do
    show_article
    assert_difference "StarredEntry.count", +1 do
      find("[data-behavior~=toggle_starred]:not(.starred)")
      find("[data-behavior~=toggle_starred] button").click
      wait_for_ajax
      find("[data-behavior~=toggle_starred].starred")
    end
  end

  test "mark unread" do
    show_article
    wait_for_ajax

    assert_difference "UnreadEntry.count", +1 do
      find("[data-behavior~=toggle_read] button").click
      wait_for_ajax
    end
  end

  test "media embed" do
    show_article_setup

    stub_request_file("oembed.json", /www\.youtube\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    stub_request(:head, /i\.ytimg\.com/).to_return(status: 200, body: "", headers: {})

    @entries.first.update(content: %(Iframe <iframe src="http://www.youtube.com/embed/1234"></iframe>))

    login_as(@user)

    click_link(@entries.first.title)

    sleep 1
    wait_for_ajax

    assert_selector ".embed-title", text: "Samsung Galaxy Note 9 Impressions: Underrated!"
  end

  test "diff" do
    show_article_setup

    entry = @entries.first

    entry.update(content: "<p>This is the text.</p>")
    entry.update(content: "<p>This is the new text.</p>", original: {content: entry.content})

    login_as(@user)

    click_link(@entries.first.title)

    wait_for_ajax

    find("label[for=diff_view]").click

    assert_selector "ins", text: "new"
  end

  test "direct link" do
    show_article_setup

    entry = @entries.first

    login_as(@user)

    visit entry_path(entry)

    assert_selector "#source_link h1", text: entry.title
  end

  test "newsletter" do
    show_article_setup

    entry = @entries.first
    entry.feed.newsletter!

    login_as(@user)

    click_link(@entries.first.title)

    wait_for_ajax

    find('label[for=newsletter_view]').click()

    assert_selector ".newsletter-content"
  end

  test "extract" do
    show_article
    wait_for_ajax

    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})

    find(".button-toggle-content").click

    assert_selector ".original-meta strong", text: "Originally from:"
  end
end
