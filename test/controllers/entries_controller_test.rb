require "test_helper"

class EntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    login_as @user
    get :index, xhr: true
    assert_response :success
    assert_equal @entries.length, assigns(:entries).length
  end

  test "should get unread" do
    mark_unread(@user)
    @user.unread_entries.where(entry_id: @entries.first.id).delete_all
    login_as @user
    get :unread, xhr: true
    assert_response :success
    assert_equal assigns(:entries).length, @user.unread_entries.length
  end

  test "should get starred" do
    starred_entry = StarredEntry.create_from_owners(@user, @entries.first)
    login_as @user
    get :starred, xhr: true
    assert_response :success
    assert_equal assigns(:entries).first, starred_entry.entry
  end

  test "should get show" do
    login_as @user
    get :show, params: {id: @entries.first}, xhr: true
    assert_response :success
  end

  test "should get show with tweet" do
    entry = create_tweet_entry(@user.feeds.first)
    url = "https://extract.example.com/parser/user/4e4143c7bd4d8c935741d37a3c14f61a268a5b79?base64_url=aHR0cHM6Ly85dG81bWFjLmNvbS8yMDE4LzAxLzEyL2ZpbmFsLWN1dC1wcm8teC1ob3ctdG8taW1wcm92ZS1zbG93LW1vdGlvbi1pbi15b3VyLXByb2plY3RzLXZpZGVvLw=="
    stub_request_file("parsed_page.json", url, headers: {"Content-Type" => "application/json; charset=utf-8"})
    HarvestLinks.new.perform(entry.id)

    login_as @user
    get :show, params: {id: entry}, xhr: true
    assert_response :success
  end

  test "should preload" do
    login_as @user
    get :preload, params: {ids: @entries.map(&:id).join(",")}, format: :json
    data = JSON.parse(@response.body)
    @entries.each do |entry|
      assert data.key?(entry.id.to_s)
    end
  end

  test "marks feed read" do
    login_as @user
    feed = @feeds.first
    assert_difference("UnreadEntry.count", -feed.entries.length) do
      post :mark_all_as_read, params: {type: "feed", data: feed.id}, xhr: true
      assert_response :success
    end
  end

  test "marks tag read" do
    login_as @user
    feed = @feeds.first
    taggings = feed.tag(Faker::Name.name, @user)
    feed_ids = taggings.map(&:feed_id)
    feeds = Feed.where(id: feed_ids)
    assert_difference("UnreadEntry.count", -feeds.entries.length) do
      post :mark_all_as_read, params: {type: "tag", data: taggings.first.tag_id}, xhr: true
      assert_response :success
    end
  end

  test "marks starred read" do
    login_as @user

    starred_entries = @user.entries.limit(2).map { |entry|
      StarredEntry.create_from_owners(@user, entry)
    }

    assert_difference("UnreadEntry.count", -starred_entries.length) do
      post :mark_all_as_read, params: {type: "starred"}, xhr: true
      assert_response :success
    end
  end

  test "marks recently read" do
    login_as @user

    recently_read_entries = @user.entries.limit(2).map { |entry|
      @user.recently_read_entries.create!(entry: entry)
    }

    assert_difference("UnreadEntry.count", -recently_read_entries.length) do
      post :mark_all_as_read, params: {type: "recently_read"}, xhr: true
      assert_response :success
    end
  end

  test "marks updated read" do
    login_as @user

    updated_entries = @user.entries.limit(2).map { |entry|
      @user.updated_entries.create!(entry: entry, feed: entry.feed)
    }

    assert_difference("UpdatedEntry.count", -updated_entries.length) do
      post :mark_all_as_read, params: {type: "updated"}, xhr: true
      assert_response :success
    end
  end

  test "marks unread read" do
    login_as @user
    count = @user.unread_entries.count
    assert_difference("UnreadEntry.count", -count) do
      post :mark_all_as_read, params: {type: "unread"}, xhr: true
      assert_response :success
    end
  end

  test "marks all read" do
    login_as @user
    count = @user.unread_entries.count
    assert_difference("UnreadEntry.count", -count) do
      post :mark_all_as_read, params: {type: "all"}, xhr: true
      assert_response :success
    end
  end

  test "marks saved search read" do
    original_per_page = Entry.per_page
    Entry.per_page = 1

    login_as @user

    entries = @user.entries.first(2)

    saved_search = @user.saved_searches.create(query: "\"#{entries.first.title}\" OR \"#{entries.last.title}\"", name: "test")
    entries = Entry.scoped_search({query: saved_search.query}, @user)

    assert_difference("UnreadEntry.count", -entries.total_entries) do
      post :mark_all_as_read, params: {type: "saved_search", data: saved_search.id}, xhr: true
      assert_response :success
    end

    mark_unread(@user)

    assert_difference("UnreadEntry.count", -entries.total_entries) do
      post :mark_all_as_read, params: {type: "search", data: saved_search.query}, xhr: true
      assert_response :success
    end

    Entry.per_page = original_per_page
  end

  test "mark specific ids read" do
    login_as @user
    entries = @user.entries.first(2)
    assert_difference("UnreadEntry.count", -entries.length) do
      post :mark_all_as_read, params: {ids: entries.map(&:id).join(",")}, xhr: true
      assert_response :success
    end
  end

  test "mark read respects date cap" do
    login_as @user
    date = @user.unread_entries.order(created_at: :asc).limit(1).take.created_at.iso8601(6)
    assert @user.unread_entries.count > 1
    assert_difference("UnreadEntry.count", -1) do
      post :mark_all_as_read, params: {type: "all", date: date}, xhr: true
      assert_response :success
    end
  end

  test "should get search" do
    login_as @user
    get :search, params: {query: "\"#{@entries.first.title}\""}, xhr: true
    assert_response :success
    assert_equal 1, assigns(:entries).total_entries
  end

  test "should get diff" do
    login_as @user
    entry = @user.entries.first
    entry.update(content: "<p>This is the test.</p>")
    entry.update(content: "<p>This is the text.</p>", original: {content: entry.content})
    get :diff, params: {id: entry}, xhr: true
    assert_response :success
    assert_match /inline-diff/, assigns(:content)
  end

  test "should get newsletter" do
    entry = @user.entries.first
    get :newsletter, params: {id: entry.public_id}
    assert_response :success
  end
end
