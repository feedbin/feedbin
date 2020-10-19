require "test_helper"

class UnreadLimiterTest < ActiveSupport::TestCase
  setup do
    ENV["ENTRY_LIMIT"] = "5"
    @count = ENV["ENTRY_LIMIT"].to_i + 60

    @user = users(:ben)
    @feed = @user.feeds.first
    Feed.reset_counters(@feed.id, :subscriptions)
    @entries = @count.times.map {
      @feed.entries.create!(
        content: Faker::Lorem.paragraph,
        public_id: SecureRandom.hex,
        published: Time.now
      )
    }
  end

  test "should remove UnreadEntries" do
    assert_difference -> { UnreadEntry.where(entry_id: @entries.map(&:id)).count }, -change do
      UnreadLimiter.new.perform(@feed.id)
    end

    @entries.each_with_index do |entry, index|
      if index < change
        refute @user.unread_entries.where(entry_id: entry.id).present?
      else
        assert @user.unread_entries.where(entry_id: entry.id).present?
      end
    end
  end

  private

  def change
    ((@count - ENV["ENTRY_LIMIT"].to_i) * 0.05).to_i
  end

end
