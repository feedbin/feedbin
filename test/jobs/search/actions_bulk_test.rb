require "test_helper"

module Search
  class ActionsBulkTest < ActiveSupport::TestCase
    setup do
      clear_search
      @user = users(:ben)
      @entry = create_entry(@user.feeds.first)
    end

    test "should mark all read" do
      SearchIndexStore.new.perform("Entry", @entry.id)
      UnreadEntry.create_from_owners(@user, @entry)

      action = Sidekiq::Testing.inline! do
        @user.actions.create(feed_ids: [@entry.feed.id], query: "\"#{@entry.title}\"", actions: ["mark_read"])
      end
      $search[:main].with { _1.refresh }

      assert_difference -> { UnreadEntry.count }, -1 do
        ActionsBulk.new.perform(action.id, @user.id)
      end
    end
  end
end


