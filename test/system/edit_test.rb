require "application_system_test_case"

class EditTest < ApplicationSystemTestCase

  test "Edit feed" do

    show_article_setup
    login_as(@user)

    feed_name = "New Name"
    tag_name = "Tag"

    within ".feeds-column" do
      click_link @feed.title
      find("[data-behavior~=feed_settings]").click
    end

    wait_for_ajax

    find(".modal [data-behavior~=autofocus]").set(feed_name)
    find("[data-behavior~=add_tag]").click
    find("[placeholder=Tag]").set(tag_name)
    find(".modal form input[type=submit]").click

    wait_for_ajax

    within ".entries" do
      click_link feed_name
    end

    assert_equal feed_name, @user.subscriptions.where(feed: @feed).first.title

  end

  test "Edit tag" do

    show_article_setup

    tag_name = "Tag Name"
    new_tag_name = "New Name"
    @feed.tag(tag_name, @user)

    login_as(@user)

    within ".feeds-column" do
      click_link tag_name
      find("[data-behavior~=feed_settings]").click
    end

    wait_for_ajax

    find(".modal [data-behavior~=autofocus]").set(new_tag_name)
    find(".modal form input[type=submit]").click

    wait_for_ajax

    click_link new_tag_name

    assert_equal new_tag_name, @user.tags.first.name

  end

  test "Edit saved search" do

    show_article_setup

    search_name = "Search Name"
    new_search_name = "New Search Name"
    search = @user.saved_searches.create!(query: @entries.first.title, name: search_name)

    login_as(@user)

    within ".feeds-column" do
      click_link search_name
      find("[data-behavior~=feed_settings]").click
    end

    wait_for_ajax

    find(".modal [data-behavior~=autofocus]").set(new_search_name)
    find(".modal form input[type=submit]").click

    wait_for_ajax

    click_link new_search_name

    assert_equal new_search_name, search.reload.name

  end


end
