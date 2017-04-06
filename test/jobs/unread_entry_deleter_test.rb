require 'test_helper'

class UnreadEntryDeleterTest < ActiveSupport::TestCase
  test "should remvoe unread_entries" do
    user = User.first
    feed = user.feeds.first
    count = entries = (1..10).to_a.sample
    count.times do
      entry = feed.entries.create(public_id: SecureRandom.hex, published: 2.months.ago)
      UnreadEntry.create_from_owners(user, entry)
    end
    assert_difference "UnreadEntry.count", -count do
      UnreadEntryDeleter.new().perform(user.id)
    end
  end
end
