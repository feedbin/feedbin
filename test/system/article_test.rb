require "application_system_test_case"

class ArticleTest < ApplicationSystemTestCase
  test "Show article" do
    show_article
    assert_text @entries.first.content
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
    assert_difference "UnreadEntry.count", +1 do
      find("[data-behavior~=toggle_read].read")
      find("[data-behavior~=toggle_read] button").click
      wait_for_ajax
      find("[data-behavior~=toggle_read]:not(.read)")
    end
  end
end
