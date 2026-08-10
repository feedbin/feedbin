require "application_system_test_case"

# Browser-level checks for the Wave 4 XSS fixes. The unit and integration tests
# assert on strings; these assert that a real browser does not execute the
# payload and does not build the elements Feedbin's own JS dispatches on.
#
# Feedbin has no CSP, so nothing here is backstopped by one — if a payload
# reaches the DOM in an executable shape, it runs.
class XssTest < ApplicationSystemTestCase
  # 137 — a tag name reaches the search autocomplete. Tag names are not only
  # self-supplied: Import#create_tags builds them from the outline titles of an
  # uploaded OPML file.
  test "a tag name is rendered as text in the search autocomplete" do
    show_article_setup
    payload = %{XSS137<img src=x onerror="window.__xss137='executed'">}
    tag = Tag.create!(name: payload)
    @user.taggings.create!(tag: tag, feed: @feed)

    login_as(@user)
    wait_for_ajax

    page.execute_script("window.__xss137 = 'not executed'")

    find("[data-event-identifier-param=toggle-search]").click
    wait_for_ajax
    find("[data-search-token-target~=query]").fill_in with: "XSS137"

    # Wait for the debounced autocomplete to render before inspecting it.
    all("[data-search-token-index-param]", minimum: 1)

    assert_equal "not executed", page.evaluate_script("window.__xss137"),
      "the tag name executed as markup"

    injected = page.evaluate_script(
      "document.querySelectorAll('[data-search-token-index-param] [data-template~=text] img').length"
    )
    assert_equal 0, injected, "the tag name produced a live element"

    # The list also carries a "Search for …" row, so match on the whole text
    # rather than picking a row by position.
    rows = all("[data-search-token-index-param] [data-template~=text]").map { it.text }
    assert_includes rows, payload, "the tag name should render literally, as its own text"
  end

  # 140 — the other half of the same change. user_titles used to be HTML-escaped
  # server side to make the innerHTML sink above safe; with that sink gone the
  # escape only showed up as literal entities.
  test "a feed title with entities reads correctly in the search token" do
    show_article_setup
    title = %{XSS140 Ben & Jerry's <news>}
    @user.subscriptions.find_by(feed: @feed).update!(title: title)

    login_as(@user)
    wait_for_ajax

    find("[data-event-identifier-param=toggle-search]").click
    wait_for_ajax
    find("[data-search-token-target~=query]").fill_in with: "XSS140"

    # The autocomplete fires behind a debounce; all(minimum:) waits for the
    # suggestions to actually render.
    all("[data-search-token-index-param]", minimum: 2)[1].click

    token = find("[data-action='search-token#deleteToken:prevent']")
    assert_equal title, token.text(:all), "the token should show the title, not its entities"
  end

  # 018 — Feedbin's client dispatches on data-behavior and data-iframe-*, so
  # content from a feed must not be able to supply them.
  test "data attributes in entry content never reach the page" do
    show_article_setup
    entry = @entries.first
    entry.update!(content: <<~HTML)
      <div data-behavior="iframe_placeholder"
           data-iframe-src="https://evil.example/"
           data-iframe-host="evil.example"
           data-iframe-embed-url="https://evil.example/x.js"
           data-controller="embed-player"
           data-action="click-&gt;embed-player#showPlayer">Load embed</div>
    HTML

    login_as(@user)
    click_link(entry.title)
    wait_for_ajax

    content = "[data-content-option=default]"
    %w[data-behavior data-iframe-src data-iframe-host data-iframe-embed-url data-controller data-action].each do |attribute|
      count = page.evaluate_script("document.querySelectorAll('#{content} [#{attribute}]').length")
      assert_equal 0, count, "#{attribute} survived into the rendered entry"
    end

    assert_text "Load embed"
  end

  # 172 — the router's :id segment allows commas, parentheses and operators, and
  # HTML escaping does nothing about them inside a <script> element.
  test "an entry id carrying a script payload does not execute" do
    show_article_setup
    entry = @entries.first

    login_as(@user)
    wait_for_ajax

    # accept_alert raises ModalNotFound when no dialog appears, which is the
    # passing case here. If the payload executes, the alert opens and the block
    # succeeds instead.
    assert_raises Capybara::ModalNotFound, "the injected alert executed" do
      accept_alert(wait: 2) do
        visit "/entries/#{entry.id},alert(1)"
      end
    end

    assert_equal "feedbin.showEntry(#{entry.id})",
      page.html[/feedbin\.showEntry\([^)]*\)/],
      "the page should emit the resolved id"
  end
end
