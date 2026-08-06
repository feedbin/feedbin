require "test_helper"

class PagesEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = Feed.create!(feed_url: "https://pages.example/x", host: "pages.example", title: "P", feed_type: :pages)
    @user.subscriptions.create!(feed: @feed)
    @entry = @feed.entries.create!(content: "<p>x</p>", title: "T", url: "/x", public_id: SecureRandom.hex)
  end

  test "GET index requires login" do
    get :index, params: {id: @feed.id}
    assert_redirected_to login_url
  end

  test "GET index defaults to the unread view" do
    login_as @user
    get :index, params: {id: @feed.id}, xhr: true
    assert_response :success
    assert_equal "true", assigns(:all_unread)
  end

  test "GET index with view=view_all takes the all-entries branch" do
    login_as @user
    get :index, params: {id: @feed.id, view: "view_all"}, xhr: true
    assert_response :success
    refute assigns(:all_unread)
  end

  test "GET index with view=view_starred takes the starred branch" do
    login_as @user
    @user.starred_entries.create!(entry_id: @entry.id, feed_id: @feed.id)
    get :index, params: {id: @feed.id, view: "view_starred"}, xhr: true
    assert_response :success
    refute assigns(:all_unread)
  end

  # The inner query ordered starred_entries.created_at (when the user starred
  # it) and the outer ordered entries.created_at (when Feedbin ingested it).
  # Both read "created_at DESC" and they draw the page boundaries and the
  # displayed order from different columns, so entries jump across pages.
  test "the starred view reads back in one order across page boundaries" do
    login_as @user
    # Ingested A, B, C. Starred in a different order: C, then A, then B.
    ingested = ["A", "B", "C"].each_with_index.map { |title, index|
      entry = @feed.entries.create!(title: title, url: "/#{title}", public_id: SecureRandom.hex)
      entry.update_columns(created_at: (10 - index).minutes.ago)
      entry
    }
    star_order = [ingested[2], ingested[0], ingested[1]]
    star_order.each_with_index do |entry, index|
      star = @user.starred_entries.create!(entry_id: entry.id, feed_id: @feed.id)
      star.update_columns(created_at: (10 - index).minutes.ago)
    end
    @user.starred_entries.where(entry_id: @entry.id).delete_all

    anchor = Entry.maximum(:id)
    titles = [1, 2].flat_map { |page|
      StarredEntry.stub(:per_page, 2) do
        get :index, params: {id: @feed.id, view: "view_starred", page: page, page_anchor: anchor}, xhr: true
      end
      assigns(:entries).map(&:title)
    }

    assert_equal titles.uniq, titles, "an entry appeared on more than one page"
    # Most recently starred first, so the reverse of the order they were starred in.
    assert_equal star_order.reverse.map(&:title), titles
  end
end
