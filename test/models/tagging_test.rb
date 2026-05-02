require "test_helper"

class TaggingTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user, 2)
    @tag_a = Tag.create!(name: "TagA")
    @tag_b = Tag.create!(name: "TagB")
  end

  test "build_tag_map groups tag ids by feed id" do
    @user.taggings.create!(tag: @tag_a, feed: @feeds[0])
    @user.taggings.create!(tag: @tag_b, feed: @feeds[0])
    @user.taggings.create!(tag: @tag_a, feed: @feeds[1])

    map = @user.taggings.build_tag_map

    assert_equal Set.new([@tag_a.id, @tag_b.id]), Set.new(map[@feeds[0].id])
    assert_equal [@tag_a.id], map[@feeds[1].id]
  end

  test "build_tag_map excludes feeds whose feed_type is pages" do
    page_feed = Feed.create!(feed_url: "https://example.com/page", host: "example.com", title: "Page", feed_type: :pages)
    @user.subscriptions.create!(feed: page_feed)
    @user.taggings.create!(tag: @tag_a, feed: page_feed)

    map = @user.taggings.build_tag_map

    refute_includes map.keys, page_feed.id
  end

  test "build_feed_map groups feed ids by tag id" do
    @user.taggings.create!(tag: @tag_a, feed: @feeds[0])
    @user.taggings.create!(tag: @tag_a, feed: @feeds[1])
    @user.taggings.create!(tag: @tag_b, feed: @feeds[0])

    map = @user.taggings.build_feed_map

    assert_equal Set.new([@feeds[0].id, @feeds[1].id]), Set.new(map[@tag_a.id])
    assert_equal [@feeds[0].id], map[@tag_b.id]
  end

  test "creating a tagging triggers a TouchActions search job for matching actions" do
    @user.taggings.create!(tag: @tag_a, feed: @feeds[0])
    action = @user.actions.create!(title: "matching", query: "x", tag_ids: [@tag_a.id], actions: ["mark_read"])
    Search::TouchActions.jobs.clear

    @user.taggings.create!(tag: @tag_a, feed: @feeds[1])

    assert_equal 1, Search::TouchActions.jobs.size
    assert_includes Search::TouchActions.jobs.last["args"].first, action.id
  end
end
