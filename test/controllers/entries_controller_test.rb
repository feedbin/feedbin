require 'test_helper'

class EntriesControllerTest < ActionController::TestCase
  setup do
    flush_redis
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    login_as @user
    xhr :get, :index
    assert_response :success
    assert_equal @entries.length, assigns(:entries).length
  end

  test "should get unread" do
    mark_unread
    @user.unread_entries.where(entry_id: @entries.first.id).delete_all
    login_as @user
    xhr :get, :unread
    assert_response :success
    assert_equal assigns(:entries).length, @user.unread_entries.length
  end

  test "should get starred" do
    starred_entry = StarredEntry.create_from_owners(@user, @entries.first)
    login_as @user
    xhr :get, :starred
    assert_response :success
    assert_equal assigns(:entries).first, starred_entry.entry
  end

  test "should get show" do
    login_as @user
    xhr :get, :show, id: @entries.first
    assert_response :success
  end

  test "should get content" do
    login_as @user
    content = Faker::Lorem.paragraph
    struct = OpenStruct.new(content: content)
    ReadabilityParser.stub :parse, struct do
      xhr :post, :content, id: @entries.first, content_view: 'true'
    end
    assert_equal assigns(:content), content
    assert_response :success
  end

  test "should preload" do
    login_as @user
    get :preload, ids: @entries.map(&:id).join(','), format: :json
    data = JSON.parse(@response.body)
    @entries.each do |entry|
      assert data.key?(entry.id.to_s)
    end
  end

  test "marks feed read" do
    login_as @user
    feed = @feeds.first
    assert_difference('UnreadEntry.count', -feed.entries.length) do
      xhr :post, :mark_all_as_read, type: 'feed', data: feed.id
      assert_response :success
    end
  end

  test "marks tag read" do
    login_as @user
    feed = @feeds.first
    taggings = feed.tag(Faker::Name.name, @user)
    feed_ids = taggings.map(&:feed_id)
    feeds = Feed.where(id: feed_ids)
    assert_difference('UnreadEntry.count', -feeds.entries.length) do
      xhr :post, :mark_all_as_read, type: 'tag', data: taggings.first.tag_id
      assert_response :success
    end
  end

  test "marks starred read" do
    login_as @user

    starred_entries = @user.entries.limit(2).map do |entry|
      StarredEntry.create_from_owners(@user, entry)
    end

    assert_difference('UnreadEntry.count', -starred_entries.length) do
      xhr :post, :mark_all_as_read, type: 'starred'
      assert_response :success
    end
  end

  test "marks recently read" do
    login_as @user

    recently_read_entries = @user.entries.limit(2).map do |entry|
      @user.recently_read_entries.create(entry: entry)
    end

    assert_difference('UnreadEntry.count', -recently_read_entries.length) do
      xhr :post, :mark_all_as_read, type: 'recently_read'
      assert_response :success
    end
  end

  test "marks updated read" do
    login_as @user

    updated_entries = @user.entries.limit(2).map do |entry|
      @user.updated_entries.create(entry: entry)
    end

    assert_difference('UpdatedEntry.count', -updated_entries.length) do
      xhr :post, :mark_all_as_read, type: 'updated'
      assert_response :success
    end
  end

  test "marks unread read" do
    login_as @user
    count = @user.unread_entries.count
    assert_difference('UnreadEntry.count', -count) do
      xhr :post, :mark_all_as_read, type: 'unread'
      assert_response :success
    end
  end

  test "marks all read" do
    login_as @user
    count = @user.unread_entries.count
    assert_difference('UnreadEntry.count', -count) do
      xhr :post, :mark_all_as_read, type: 'all'
      assert_response :success
    end
  end

  test "marks saved search read" do
    Entry.per_page = 1

    login_as @user

    entries = @user.entries.first(2)

    saved_search = @user.saved_searches.create(query: "\"#{entries.first.title}\" OR \"#{entries.last.title}\"", name: 'test')
    entries = Entry.scoped_search({query: saved_search.query}, @user)

    assert_difference('UnreadEntry.count', -entries.total_entries) do
      xhr :post, :mark_all_as_read, type: 'saved_search', data: saved_search.id
      assert_response :success
    end

    mark_unread

    assert_difference('UnreadEntry.count', -entries.total_entries) do
      xhr :post, :mark_all_as_read, type: 'search', data: saved_search.query
      assert_response :success
    end

  end

  test "mark specific ids read" do
    login_as @user
    entries = @user.entries.first(2)
    assert_difference('UnreadEntry.count', -entries.length) do
      xhr :post, :mark_all_as_read, ids: entries.map(&:id).join(',')
      assert_response :success
    end
  end

  test "mark read respects date cap" do
    login_as @user
    date = @user.unread_entries.order(created_at: :asc).limit(1).take.created_at.iso8601(6)
    assert @user.unread_entries.count > 1
    assert_difference('UnreadEntry.count', -1) do
      xhr :post, :mark_all_as_read, type: 'all', date: date
      assert_response :success
    end
  end

  test "should get search" do
    login_as @user
    xhr :get, :search, query: "\"#{@entries.first.title}\""
    assert_response :success
    assert_equal 1, assigns(:entries).total_entries
  end

  test "should get diff" do
    login_as @user
    entry = @user.entries.first
    entry.update(content: '<p>This is the test.</p>')
    entry.update(content: '<p>This is the text.</p>', original: {content: entry.content})
    xhr :get, :diff, id: entry
    assert_response :success
    assert_match /inline-diff/, assigns(:content)
  end

  test "should get newsletter" do
    entry = @user.entries.first
    get :newsletter, id: entry.public_id
    assert_response :success
  end

  private

  def mark_unread
    @user.entries.each do |entry|
      UnreadEntry.create_from_owners(@user, entry)
    end
  end


end
