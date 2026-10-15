require "application_system_test_case"

class MarkReadTest < ApplicationSystemTestCase
  setup do
    @user = users(:ben)
    @user.update!(mark_as_read_confirmation: false)
    @tagged, *@untagged = create_feeds(@user, 3)
    @tag = @tagged.tag("Folder", @user).first.tag
  end

  test "source menu marks only the tag read" do
    login_as(@user)
    assert_selector ".entries li", count: 3

    mark_tag_read_from_menu

    assert_equal 0, UnreadEntry.where(user: @user, feed: @tagged).count
    assert_equal @untagged.size, UnreadEntry.where(user: @user, feed: @untagged).count
  end

  test "source menu marks the shown tag read" do
    login_as(@user)
    find("[data-feed-id=tag-#{@tag.id}] > .feed-link").click
    assert_selector ".entries li", count: 1

    mark_tag_read_from_menu

    assert_equal 0, UnreadEntry.where(user: @user, feed: @tagged).count
    assert_equal @untagged.size, UnreadEntry.where(user: @user, feed: @untagged).count
  end

  private

  def mark_tag_read_from_menu
    tag_link = find("[data-feed-id=tag-#{@tag.id}] > .feed-link")
    tag_link.hover
    tag_link.find("[data-behavior~=toggle_source_menu]").click
    find(".source-menu-container [data-behavior~=menu_mark_read]").click
    wait_for_ajax
  end
end
