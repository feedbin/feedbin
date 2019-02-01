require "test_helper"

class SearchIndexStoreTest < ActiveSupport::TestCase
  setup do
    clear_search
    @user = users(:ben)
    @entry = create_entry(@user.feeds.first)
  end

  test "should index entry" do
    SearchIndexStore.new.perform("Entry", @entry.id)
    Entry.__elasticsearch__.refresh_index!
    entry = Entry.__elasticsearch__.client.get(id: @entry.id, index: Entry.index_name, type: Entry.document_type)

    assert entry["found"]
  end

  test "should percolate entry" do
    action = nil
    Sidekiq::Testing.inline! do
      action = @user.actions.create(feed_ids: [@entry.feed.id], query: "\"#{@entry.title}\"")
    end
    Entry.__elasticsearch__.refresh_index!

    assert_difference "ActionsPerform.jobs.size", +1 do
      SearchIndexStore.new.perform("Entry", @entry.id)
    end

    entry_id, action_ids = ActionsPerform.jobs.first["args"]
    assert_equal entry_id, @entry.id
    assert_equal action_ids, [action.id]
  end

  test "should not percolate entry" do
    Sidekiq::Testing.inline! do
      action = @user.actions.create(feed_ids: [@entry.feed.id], query: "\"#{@entry.title}\"")
    end
    Entry.__elasticsearch__.refresh_index!

    assert_no_difference "ActionsPerform.jobs.size", +1 do
      SearchIndexStore.new.perform("Entry", @entry.id, true)
    end
  end
end
