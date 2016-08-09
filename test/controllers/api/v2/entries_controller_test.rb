require 'test_helper'

class Api::V2::EntriesControllerTest < ApiControllerTestCase

  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    assert_equal @entries.length, assigns(:entries).length
  end

  test "should show entry" do
    login_as @user
    entry = @entries.first

    get :show, id: entry, format: :json
    assert_response :success

    result = parse_json
    assert_has_keys(entry_keys, result)
  end

  test "should show entry with all keys" do
    login_as @user
    entry = @entries.first

    get :show, id: entry, format: :json, include_content_diff: 'true', include_enclosure: 'true', include_original: 'true'
    assert_response :success

    result = parse_json
    assert_has_keys(entry_keys(true), result)
  end

  test "should get text format" do
    login_as @user
    get :text, id: @entries.first, format: :json
    assert_response :success
  end

  test "should get specific ids" do
    login_as @user
    entries = @entries.sample(2)
    get :index, format: :json, ids: entries.map(&:id).join(',')
    assert_response :success
    assert_equal_ids(entries, parse_json)
  end

  test "should get starred entries" do
    login_as @user
    entries = @entries.sample(2)

    entries.each do |entry|
      StarredEntry.create_from_owners(@user, entry)
    end

    get :index, format: :json, starred: 'true'
    assert_response :success
    assert_equal_ids(entries, parse_json)
  end

  test "should get entries since date" do
    login_as @user
    entry = @entries.sample
    date = entry.created_at.iso8601(6)
    get :index, format: :json, since: date

    expected = Entry.where("created_at > :time", {time: entry.created_at})
    assert_equal_ids expected, parse_json
  end

  private

  def entry_keys(all = false)
    keys = %w[id feed_id title author summary created_at published url content]
    if all
      keys = keys.concat(%w[content_diff enclosure original])
    end
    keys
  end

end
