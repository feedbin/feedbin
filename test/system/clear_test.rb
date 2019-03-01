require "application_system_test_case"

class ClearTest < ApplicationSystemTestCase

  test "Clear Recently Read" do

    user = users(:ben)
    login_as(user)
    show_article_setup

    user.recently_read_entries.create!(entry: @entries.first)

    click_link "Recently Read"

    accept_confirm do
      find(".collection-recently-read input[type=submit]").click
    end

    wait_for_ajax

    assert_equal(0, user.recently_read_entries.count)
  end

  test "Clear Recently Played" do

    user = users(:ben)
    login_as(user)
    show_article_setup

    user.recently_played_entries.create!(entry: @entries.first)

    click_link "Recently Played"

    accept_confirm do
      find(".collection-recently-played input[type=submit]").click
    end

    wait_for_ajax

    assert_equal(0, user.recently_played_entries.count)
  end

end
