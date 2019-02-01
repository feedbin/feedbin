require "application_system_test_case"

class SubscribeTest < ApplicationSystemTestCase
  test "Subscribe URL" do
    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("atom.xml", feed_url)

    user = users(:ben)
    login_as(user)

    visit root_path(subscribe: feed_url)

    within(".modal-purpose-subscribe") do
      page.execute_script("$('.modal-purpose-subscribe [data-behavior~=feeds_search]').submit()")
      find("[data-behavior~=subscription_options]")
      click_button "Add"
    end

    feed = Feed.find_by_feed_url!(feed_url)

    feed.entries.first(3) do |entry|
      expect_text(entry.title)
    end
  end

  test "Subscribe form" do
    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("atom.xml", feed_url)

    user = users(:ben)
    login_as(user)

    find("[data-behavior~=show_subscribe]").click

    within(".modal-purpose-subscribe") do
      fill_in "q", with: feed_url
      page.execute_script("$('.modal-purpose-subscribe [data-behavior~=feeds_search]').submit()")
      find("[data-behavior~=subscription_options]")
      click_button "Add"
    end

    feed = Feed.find_by_feed_url!(feed_url)

    feed.entries.first(3) do |entry|
      expect_text(entry.title)
    end
  end
end
