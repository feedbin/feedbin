require "test_helper"

class EntryDeleterTest < ActiveSupport::TestCase
  setup do
    count = (5..16).to_a
    ENV["ENTRY_LIMIT"] = count.sample.to_s

    @user = users(:ben)
    @feed = @user.feeds.first
    Feed.reset_counters(@feed.id, :subscriptions)
    @entries = (ENV["ENTRY_LIMIT"].to_i + count.sample).times.map {
      @feed.entries.create!(
        content: Faker::Lorem.paragraph,
        public_id: SecureRandom.hex,
      )
    }
  end

  test "should limit total entries" do
    assert @feed.entries.count > ENV["ENTRY_LIMIT"].to_i
    EntryDeleter.new.perform(@feed.id)
    assert_equal ENV["ENTRY_LIMIT"].to_i, @feed.reload.entries.count
  end

  test "should skip protected feeds" do
    @feed.update(protected: true)
    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should skip starred entries" do
    @entries.each do |entry|
      StarredEntry.create_from_owners(@user, entry)
    end
    assert_no_difference -> { @feed.entries.count } do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should remove UnreadEntries" do
    @entries.each do |entry|
      UnreadEntry.create_from_owners(@user, entry)
    end
    assert_difference -> { UnreadEntry.where(entry_id: entry_ids).count }, -removed_count do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should remove UpdatedEntries" do
    @entries.each do |entry|
      UpdatedEntry.create_from_owners(@user.id, entry)
    end
    assert_difference -> { UpdatedEntry.where(entry_id: entry_ids).count }, -removed_count do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should enqueue SearchIndexRemove" do
    assert_difference "SearchIndexRemove.jobs.size", +1 do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should remove ids from created_at cache" do
    key_created_at = FeedbinUtils.redis_created_at_key(@feed.id)
    assert_difference -> { $redis[:entries].with { |redis| redis.zcard(key_created_at) } }, -removed_count do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  test "should remove ids from published cache" do
    key_published = FeedbinUtils.redis_published_key(@feed.id)
    assert_difference -> { $redis[:entries].with { |redis| redis.zcard(key_published) } }, -removed_count do
      EntryDeleter.new.perform(@feed.id)
    end
  end

  private

  def removed_count
    @entries.count - ENV["ENTRY_LIMIT"].to_i
  end

  def entry_ids
    @entries.map(&:id)
  end
end
