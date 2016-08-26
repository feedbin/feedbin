require 'test_helper'

class EntryBulkIndexTest < ActiveSupport::TestCase
  test "should bulk index entries in elasticsearch" do
    Sidekiq::Queues["worker_slow"].clear
    clear_search

    feed = Feed.first
    entries = SecureRandom.random_number(10).times.map do
      feed.entries.create(
        content: Faker::Lorem.paragraph,
        public_id: SecureRandom.hex,
      )
    end

    Sidekiq::Testing.inline! do
      EntryBulkIndex.new().perform(nil, true, Entry.last.id)
    end
    Entry.__elasticsearch__.refresh_index!

    query = {
      query: {
        filtered: {
          filter: {
            terms: { id: entries.map(&:id) }
          }
        }
      }
    }
    assert_equal entries.count, Entry.search(query).results.total
  end
end
