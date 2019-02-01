require "test_helper"

class SearchServerSetupTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Queues["worker_slow"].clear
    clear_search
    @user = users(:ben)
    feed = @user.feeds.first
    @entries = (1..10).to_a.sample.times.map {
      feed.entries.create!(
        content: Faker::Lorem.paragraph,
        public_id: SecureRandom.hex,
      )
    }
  end

  test "should bulk index entries in elasticsearch" do
    Sidekiq::Testing.inline! do
      SearchServerSetup.new.perform(nil, true, Entry.last.id)
    end
    Entry.__elasticsearch__.refresh_index!
    query = {
      query: {
        filtered: {
          filter: {
            terms: {id: @entries.map(&:id)},
          },
        },
      },
    }
    assert_equal @entries.count, Entry.search(query).results.total
  end

  test "should touch actions" do
    entry = @entries.first
    action = @user.actions.create(feed_ids: [entry.feed.id], query: "\"#{entry.title}\"")
    Sidekiq::Testing.inline! do
      SearchServerSetup.new.perform(nil, true, Entry.last.id)
    end
    Entry.__elasticsearch__.refresh_index!
    assert_not_equal(action.updated_at, action.reload.updated_at)
  end
end
