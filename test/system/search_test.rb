require "application_system_test_case"

class SearchTest < ApplicationSystemTestCase
  test "search" do
    show_article_setup

    login_as(@user)

    wait_for_ajax

    find("[data-event-identifier-param=toggle-search]").click

    wait_for_ajax

    assert find("[data-controller=search-form]").visible?

    find("[data-search-token-target~=query]").fill_in with: @feed.title

    wait_for_ajax

    all("[data-search-token-index-param]")[1].click

    wait_for_ajax

    token = find("[data-action='search-token#deleteToken:prevent']")
    assert token.visible?
    assert_equal token.text(:all), @feed.title
  end

end
