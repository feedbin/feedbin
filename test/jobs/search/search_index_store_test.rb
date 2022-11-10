require "test_helper"

module Search
  class SearchIndexStoreTest < ActiveSupport::TestCase
    setup do
      clear_search
      @user = users(:ben)
      @entry = create_entry(@user.feeds.first)
    end

    test "should index entry" do
      SearchIndexStore.new.perform("Entry", @entry.id)
      $search[:main].with { _1.refresh }
      entry = $search[:main].with { _1.get(Entry.table_name, id: @entry.id) }
      assert entry["found"]
    end

    test "should percolate entry" do
      action = nil
      Sidekiq::Testing.inline! do
        action = @user.actions.create(feed_ids: [@entry.feed.id], query: "\"#{@entry.title}\"")
      end
      $search[:main].with { _1.refresh }

      assert_difference -> { ActionsPerform.jobs.size }, +1 do
        SearchIndexStore.new.perform("Entry", @entry.id)
      end

      entry_id, action_ids = ActionsPerform.jobs.first["args"]
      assert_equal entry_id, @entry.id
      assert_equal action_ids, [action.id]
    end
  end
end