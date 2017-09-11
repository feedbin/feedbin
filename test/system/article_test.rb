require "application_system_test_case"

class ArticleTest < ApplicationSystemTestCase
  test "Show article" do
    show_article
    assert_text @entries.first.content
  end

  test "star" do
    show_article
    assert_difference "StarredEntry.count", +1 do
      find(".button-toggle-starred").click
      find(".entries li.starred")
    end
  end
end
