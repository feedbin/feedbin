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
      wait_for_ajax
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

  test "Basic auth form" do
    feed_url = "www.example.com/atom.xml"

    username = "user"
    password = "password"
    valid_auth = "Basic #{Base64.strict_encode64("#{username}:#{password}")}"

    stub_request(:get, feed_url, ).with { |request| request.headers["Authorization"] != valid_auth }.to_return(status: 401, headers: {www_authenticate: "Basic"})
    stub_request_file("atom.xml", feed_url).with(headers: {"Authorization" => valid_auth})

    user = users(:ben)
    login_as(user)

    find("[data-behavior~=show_subscribe]").click

    within(".modal-purpose-subscribe") do
      fill_in "q", with: feed_url
      page.execute_script("$('.modal-purpose-subscribe [data-behavior~=feeds_search]').submit()")
      wait_for_ajax
      page.execute_script("$('.modal-purpose-subscribe [data-behavior~=submit_add]').submit()")
      wait_for_ajax
    end

    assert_selector "[data-behavior~=notification_container]", text: "Incorrect username or password."

    within(".modal-purpose-subscribe") do
      fill_in "username", with: username
      fill_in "password", with: password
      page.execute_script("$('.modal-purpose-subscribe [data-behavior~=submit_add]').submit()")
      wait_for_ajax
      assert_selector "p", text: "A fast, simple RSS feed reader that delivers a great reading"
    end

  end
end
