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

  test "a feed with no title does not take down the whole autocomplete" do
    show_article_setup

    # feeds.title is nullable, and a JSON Feed that omits its title persists NULL.
    @feed.update_columns(title: nil)

    login_as(@user)

    wait_for_ajax

    page.execute_script(<<~JS)
      window.stimulusErrors = []
      window.Stimulus.handleError = (error) => { window.stimulusErrors.push(String(error)) }
    JS

    find("[data-event-identifier-param=toggle-search]").click

    wait_for_ajax

    find("[data-search-token-target~=query]").fill_in with: "un"

    wait_for_ajax

    assert_empty page.evaluate_script("window.stimulusErrors")
    assert_selector "[data-search-token-index-param]", minimum: 1
  end

end
