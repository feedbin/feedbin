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

    click_link(entry.tweet.tweet_summary)

    assert_selector ".tweet-text", text: entry.tweet.tweet_summary
    # A tweet has no feed title in the entry list; the toolbar still names the feed.
    assert_selector ".entry-toolbar .entry-feed-title", text: entry.feed.title
  end

  test "star" do
    show_article
    wait_for_ajax
    assert_selector "[data-entry-toolbar-starred-value='false']"

    assert_difference "StarredEntry.count", +1 do
      find(".entry-toolbar .button-toggle-starred").click
      wait_for_ajax
    end
    assert_selector "[data-entry-toolbar-starred-value='true']"
    assert_selector ".entry-toolbar .button-toggle-starred .icon-star-on", visible: true
  end

  test "star with the s key" do
    show_article
    wait_for_ajax

    assert_difference "StarredEntry.count", +1 do
      find("body").send_keys("s")
      wait_for_ajax
    end
    assert_selector "[data-entry-toolbar-starred-value='true']"
  end

  test "mark unread" do
    show_article
    wait_for_ajax

    assert_difference "UnreadEntry.count", +1 do
      find(".entry-toolbar .button-toggle-read").click
      wait_for_ajax
    end
    assert_selector "[data-entry-toolbar-read-value='false']"
  end

  test "mark unread with the m key" do
    show_article
    wait_for_ajax

    assert_difference "UnreadEntry.count", +1 do
      find("body").send_keys("m")
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

    wait_for_ajax

    assert_text "Samsung Galaxy Note 9 Impressions: Underrated!"
  end

  test "twitter embed" do
    show_article_setup

    entry = create_tweet_entry(@entries.first.feed)

    SaveTwitterUsers.new.perform(entry.id)

    stub_request_file("twitter_oembed.json", /publish\.twitter\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})

    @entries.first.update(content: %(Tweet <blockquote class="twitter-tweet"><a href="https://twitter.com/9to5mac/status/1280625051822436353">May 24, 2019</a></blockquote>))

    login_as(@user)

    click_link(@entries.first.title)

    wait_for_ajax

    # The icons path sends a miss to camo, which cannot load in a test, so
    # the default avatar takes its place. TwitterEmbedPartialTest checks the
    # path itself.
    assert_selector ".profile-image img[src*='favicon-profile-default']"
    assert_selector ".tweet-body", text: "iOS 14 will let you"
  end

  test "diff" do
    show_article_setup

    entry = @entries.first

    entry.update(content: "<p>This is the text.</p>")
    new_content = "<p>This is the new text.</p>"
    entry.update(content: new_content, compressed_original_content: OriginalContent.compress(entry.content, base: new_content))

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
    assert_selector ".entry-toolbar .entry-feed-title", text: @feed.title

    assert_difference "StarredEntry.count", +1 do
      find(".entry-toolbar .button-toggle-starred").click
      wait_for_ajax
    end
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

    extract = stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})

    find(".button-toggle-content").click

    assert_selector ".original-meta strong", text: "Originally from:"
    assert_selector "[data-entry-toolbar-extract-value='true']"

    find(".button-toggle-content").click
    wait_for_ajax

    assert_selector "[data-entry-toolbar-extract-value='false']"
    assert_no_selector ".original-meta", visible: true
    assert_requested extract, times: 1
  end

  test "extract with the c key" do
    show_article
    wait_for_ajax
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})

    find("body").send_keys("c")

    assert_selector ".original-meta strong", text: "Originally from:"
  end

  test "a press while extract loads aborts it" do
    show_article
    wait_for_ajax
    body = File.read(support_file("parsed_page.json"))
    stub_request(:get, /extract\.example\.com/).to_return do
      sleep 1
      {body: body, headers: {"Content-Type" => "application/json; charset=utf-8"}}
    end

    find("body").send_keys("c")
    assert_selector "[data-entry-toolbar-loading-value='true']"
    find("body").send_keys("c")

    assert_selector "[data-entry-toolbar-loading-value='false'][data-entry-toolbar-extract-value='false']"
    sleep 1.5
    assert_no_selector ".original-meta"
  end

  test "automatic extract for a sticky feed does not change the setting" do
    show_article_setup
    @user.update!(sticky_view_inline: "1")
    @user.subscriptions.where(feed: @feed).update_all(view_inline: true)
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    login_as(@user)

    click_link(@entries.first.title)

    assert_selector ".original-meta strong", text: "Originally from:"
    wait_for_ajax
    assert @user.subscriptions.find_by(feed: @feed).view_inline
  end

  test "automatic extract on a full page load" do
    show_article_setup
    @user.update!(sticky_view_inline: "1")
    @user.subscriptions.where(feed: @feed).update_all(view_inline: true)
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    login_as(@user)

    visit entry_path(@entries.first)

    assert_selector ".original-meta strong", text: "Originally from:"
    assert_selector "[data-entry-toolbar-extract-value='true']"
  end

  test "settings menu opens from the entry toolbar and closes with escape" do
    show_article
    wait_for_ajax

    find(".entry-toolbar [data-behavior~=toggle_settings_menu]").click
    assert_selector ".settings-menu", text: "Subscriptions"

    find("body").send_keys(:escape)
    assert_no_selector ".settings-menu", visible: true
  end

  test "settings menu closes when another entry opens" do
    show_article_setup
    other_entry = create_entry(@feed)
    login_as(@user)
    click_link(@entries.first.title)
    wait_for_ajax

    find(".entry-toolbar [data-behavior~=toggle_settings_menu]").click
    assert_selector ".settings-menu", text: "Subscriptions"

    click_link(other_entry.title)
    assert_selector ".entry-toolbar", count: 1
    assert_selector "#source_link h1", text: other_entry.title
    assert_no_selector ".settings-menu", visible: true
  end

  test "settings menu opens from the account toolbar" do
    show_article_setup
    login_as(@user)

    find(".account-toolbar [data-behavior~=toggle_settings_menu]").click
    assert_selector ".settings-menu", text: "Subscriptions"
  end

  test "settings menu and format menu are not open together" do
    show_article
    wait_for_ajax

    find(".entry-toolbar [data-behavior~=toggle_format_menu]").click
    assert_selector ".format-palette", visible: true

    find(".entry-toolbar [data-behavior~=toggle_settings_menu]").click
    assert_selector ".settings-menu", text: "Subscriptions"
    assert_no_selector ".format-palette", visible: true
  end

  test "page renders one settings menu" do
    show_article
    wait_for_ajax

    assert_selector "[data-behavior~=toggle_settings_menu]", minimum: 2, visible: :all
    assert_selector "[data-nav=dropdown]", count: 1, visible: :all
  end

  # ---- one toolbar for every entry ------------------------------------------

  test "switching entries moves the toolbar to the new entry" do
    entry_a, entry_b = two_feed_entries
    login_as(@user)
    click_link(entry_a.title)
    wait_for_ajax
    click_link(entry_b.title)
    wait_for_ajax

    assert_selector ".entry-toolbar", count: 1
    within(".entry-toolbar") do
      assert_selector ".entry-feed-title", text: entry_b.feed.title
      assert_selector ".favicon-wrap"
    end
    assert_no_selector ".entry-toolbar .icon-delete", visible: true

    find(".entry-toolbar .button-toggle-starred").click
    wait_for_ajax
    assert StarredEntry.exists?(user: @user, entry: entry_b)
    refute StarredEntry.exists?(user: @user, entry: entry_a)
  end

  test "a star request keeps its entry when another entry opens" do
    entry_a, entry_b = two_feed_entries
    login_as(@user)
    click_link(entry_a.title)
    wait_for_ajax

    find(".entry-toolbar .button-toggle-starred").click
    click_link(entry_b.title)
    wait_for_ajax

    assert StarredEntry.exists?(user: @user, entry: entry_a)
    refute StarredEntry.exists?(user: @user, entry: entry_b)
  end

  # Any click on the page closes a dropdown, so the menu opens and entry B
  # opens from a script, the way a keyboard shortcut opens it. A user with no
  # share services gets navigator.share in place of the dropdown.
  test "the share menu closes when another entry opens" do
    entry_a, entry_b = two_feed_entries
    login_as(@user)
    click_link(entry_a.title)
    wait_for_ajax
    assert page.evaluate_script("feedbin.entries[#{entry_b.id}] !== undefined")

    page.execute_script("$('.entry-toolbar .button-toggle-share-menu').addClass('open')")
    assert_selector ".entry-toolbar .dropdown-wrap.open"

    page.execute_script("feedbin.showEntry(#{entry_b.id})")
    assert_selector ".entry-toolbar .entry-feed-title", text: entry_b.feed.title
    assert_no_selector ".entry-toolbar .dropdown-wrap.open"
  end

  test "delete a pages entry" do
    show_article_setup
    feed = Feed.create!(feed_url: "https://pages.example/x", host: "pages.example", title: "Pages", feed_type: :pages)
    @user.subscriptions.create!(feed: feed)
    entry = create_entry(feed)
    login_as(@user)
    click_link(entry.title)
    wait_for_ajax

    accept_confirm("Are you sure you want to delete this page?") do
      find(".entry-toolbar [data-action~='click->entry-toolbar#delete']").click
    end
    wait_for_ajax

    assert_no_selector "[data-behavior~=entries_target] [data-entry-id='#{entry.id}']"
    assert_no_selector ".entry-column.has-content"
    assert_no_difference "StarredEntry.count" do
      find("body").send_keys("s")
      wait_for_ajax
    end
  end

  test "the header links to edit subscription for a subscribed feed" do
    show_article
    wait_for_ajax

    link = find(".entry-toolbar a.feed-button")
    assert_equal "/subscriptions/#{@feed.id}/edit?app=true", URI(link[:href]).request_uri
    link.click
    assert_selector "dialog h2", text: "Edit Subscription"
  end

  test "the header is not a link for a feed with no subscription" do
    show_article_setup
    feed = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other Feed")
    entry = create_entry(feed)
    StarredEntry.create_from_owners(@user, entry)
    login_as(@user)
    visit entry_path(entry)

    assert_selector ".entry-toolbar span.feed-button .entry-feed-title", text: "Other Feed"
    assert_no_selector ".entry-toolbar a.feed-button", visible: true
  end

  test "the header shows the custom feed title" do
    show_article_setup
    @user.subscriptions.where(feed: @feed).update_all(title: "My Title")
    login_as(@user)
    click_link(@entries.first.title)
    wait_for_ajax

    assert_selector ".entry-toolbar .entry-feed-title", text: "My Title"
  end

  test "a rename changes the header after another entry opened" do
    entry_a, entry_b = two_feed_entries
    login_as(@user)
    click_link(entry_a.title)
    wait_for_ajax
    click_link(entry_b.title)
    wait_for_ajax

    page.execute_script(<<~JS)
      feedbin.data.user_titles[#{entry_b.feed_id}] = "Renamed"
      feedbin.applyUserTitles(false)
    JS
    assert_selector ".entry-toolbar .entry-feed-title", text: "Renamed"
  end

  test "an entry with no toolbar data turns the toolbar off" do
    show_article
    wait_for_ajax
    entry = @entries.first

    page.execute_script("delete feedbin.entries[#{entry.id}].toolbar; feedbin.showEntry(#{entry.id})")

    assert_selector "[data-entry-toolbar-entry-id-value='0']", visible: :all
    assert_selector "#source_link h1", text: entry.title
    # Nothing that still names the previous entry stays on screen.
    assert_no_selector ".entry-toolbar .entry-feed-title", visible: :all
    assert_no_selector ".entry-toolbar .button-toggle-starred", visible: true
    assert_no_selector ".entry-toolbar [data-behavior~=toggle_share_menu]", visible: true
    assert_selector ".entry-toolbar [data-behavior~=toggle_format_menu]", visible: true
    assert_no_difference "StarredEntry.count" do
      find("body").send_keys("s")
      wait_for_ajax
    end
  end

  # The toolbar stays in the page with no entry open. Its hidden share button
  # must not open a dropdown, which would send j and k to the share menu.
  test "f with no entry open leaves the share menu closed" do
    show_article_setup
    login_as(@user)
    assert_selector "[data-entry-toolbar-entry-id-value='0']", visible: :all

    find("body").send_keys("f")

    assert_no_selector ".dropdown-wrap.open", visible: :all
  end

  test "clearing the entry resets the toolbar" do
    show_article
    wait_for_ajax

    page.execute_script("feedbin.clearEntry()")

    assert_selector "[data-entry-toolbar-entry-id-value='0']", visible: :all
    assert_equal "", find("#source_link_field", visible: :all).value
    assert_no_selector ".entry-toolbar .entry-feed-title", visible: :all
    assert_no_selector ".entry-toolbar [data-behavior~=share_options] li", visible: :all
    find("body").send_keys("f")
    assert_no_selector ".dropdown-wrap.open", visible: :all
  end

  private

  def two_feed_entries
    @user = users(:ben)
    feed_a, feed_b = create_feeds(@user, 2)
    [feed_a.entries.first, feed_b.entries.first]
  end
end
