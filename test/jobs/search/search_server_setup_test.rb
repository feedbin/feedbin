require "test_helper"

module Search
  class SearchServerSetupTest < ActiveSupport::TestCase
    setup do
      flush_redis
      clear_search
      @user = users(:ben)
      feed = @user.feeds.first
      @entries = (1..10).to_a.sample.times.map {
        feed.entries.create!(
          content: Faker::Lorem.paragraph,
          public_id: SecureRandom.hex
        )
      }
    end

    test "should bulk index entries in elasticsearch" do
      Sidekiq::Testing.inline! do
        SearchServerSetup.new.build
      end
      $search[:main].with { _1.refresh }


      query = {
        query: {
          bool: {
            filter: {
              ids: {
                values: @entries.map(&:id)
              }
            }
          }
        }
      }
      assert_equal @entries.count, $search[:main].with { _1.search(Entry.table_name, query: query) }.total
    end

    test "should touch actions" do
      entry = @entries.first
      action = @user.actions.create(feed_ids: [entry.feed.id], query: "\"#{entry.title}\"")
      Sidekiq::Testing.inline! do
        SearchServerSetup.new.build
      end
      $search[:main].with { _1.refresh }
      assert_not_equal(action.updated_at, action.reload.updated_at)
    end
  end
end