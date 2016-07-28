require 'test_helper'

class EntriesControllerTest < ActionController::TestCase
  setup do
    flush_redis
    @user = users(:ben)
    @feed = feeds(:daring_fireball)
    @entries = [create_entry(@feed), create_entry(@feed)]
  end

  test "should get index" do
    login_as users(:ben)
    xhr :get, :index
    assert_response :success
    assert_equal @entries.length, assigns(:entries).length
  end

  test "should get unread" do
    mark_unread
    @user.unread_entries.where(entry_id: @entries.first.id).delete_all
    login_as users(:ben)
    xhr :get, :unread
    assert_response :success
    assert_equal assigns(:entries).length, @user.unread_entries.length
  end

  test "should get starred" do
    starred_entry = StarredEntry.create_from_owners(@user, @entries.first)
    login_as users(:ben)
    xhr :get, :starred
    assert_response :success
    assert_equal assigns(:entries).first, starred_entry.entry
  end

  test "should get show" do
    login_as users(:ben)
    xhr :get, :show, id: @entries.first
    assert_response :success
  end

  test "should get content" do
    login_as users(:ben)
    content = Faker::Lorem.paragraph
    struct = OpenStruct.new(content: content)
    ReadabilityParser.stub :parse, struct do
      xhr :post, :content, id: @entries.first, content_view: 'true'
    end
    assert_equal assigns(:content), content
    assert_response :success
  end

  test "should preload" do
    login_as users(:ben)
    get :preload, ids: @entries.map(&:id).join(','), format: :json
    data = JSON.parse(@response.body)
    @entries.each do |entry|
      assert data.key?(entry.id.to_s)
    end
  end

  private

  def mark_unread
    @user.entries.each do |entry|
      UnreadEntry.create_from_owners(@user, entry)
    end
  end

  def create_entry(feed)
    feed.entries.create(
      title: Faker::Lorem.sentence,
      url: Faker::Internet.url,
      author: Faker::Name.name,
      content: "<p>#{Faker::Lorem.paragraph}</p>",
      published: Faker::Date.backward(600),
      entry_id: Faker::Internet.slug,
      public_id: Faker::Internet.slug,
    )
  end

end
