require "application_system_test_case"

class SubscribeTest < ApplicationSystemTestCase
  test "Subscribe URL" do
    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("atom.xml", feed_url)

    user = users(:ben)
    login_as(user)

    find("[data-behavior~=show_subscribe]").click

    within("dialog") do
      fill_in "q", with: feed_url
      page.execute_script("$('dialog [data-behavior~=spinner]').submit()")
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

    within("dialog") do
      fill_in "q", with: feed_url
      page.execute_script("$('dialog [data-behavior~=spinner]').submit()")
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

    within("dialog") do
      fill_in "q", with: feed_url
      page.execute_script("$('dialog [data-behavior~=spinner]').submit()")
      find("#add_form")

      fill_in "basic_username", with: "wrong"
      fill_in "basic_password", with: "wrong"
      page.execute_script("$('dialog #add_form').submit()")

      assert_selector ".text-red-600", text: "Invalid username or password."

      fill_in "basic_username", with: username
      fill_in "basic_password", with: password
      page.execute_script("$('dialog #add_form').submit()")

      assert_selector "p", text: "A fast, simple RSS feed reader that delivers a great reading"
    end

  end
end
