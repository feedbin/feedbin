require "test_helper"

class AccountMigrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "percentage_complete is 0 when there are no items" do
    migration = @user.account_migrations.create!(api_token: "token")
    assert_equal 0, migration.percentage_complete
  end

  test "percentage_complete is 0 when all items are pending" do
    migration = @user.account_migrations.create!(api_token: "token")
    Sidekiq::Testing.fake! do
      3.times { migration.account_migration_items.create!(status: :pending) }
    end

    assert_equal 0.0, migration.percentage_complete
  end

  test "percentage_complete reflects ratio of non-pending items" do
    migration = @user.account_migrations.create!(api_token: "token")
    Sidekiq::Testing.fake! do
      migration.account_migration_items.create!(status: :pending)
      migration.account_migration_items.create!(status: :complete)
      migration.account_migration_items.create!(status: :failed)
      migration.account_migration_items.create!(status: :complete)
    end

    assert_equal 75.0, migration.percentage_complete
  end

  test "fw_streams is stored in data via store accessor" do
    migration = @user.account_migrations.create!(api_token: "token", fw_streams: {"streams" => []})
    assert_equal({"streams" => []}, migration.fw_streams)
  end

  test "streams returns a hash mapping feed_id to stream titles" do
    fw_streams = {
      "streams" => [
        {
          "title" => "News",
          "feeds" => [{"feed_id" => 1}, {"feed_id" => 2}]
        },
        {
          "title" => "Tech",
          "feeds" => [{"feed_id" => 2}]
        }
      ]
    }
    migration = @user.account_migrations.create!(api_token: "token", fw_streams: fw_streams)

    assert_equal({1 => ["News"], 2 => ["News", "Tech"]}, migration.streams)
  end

  test "streams excludes search-term streams and empty-feed streams" do
    fw_streams = {
      "streams" => [
        {"title" => "Search", "search_term" => "rails", "feeds" => [{"feed_id" => 1}]},
        {"title" => "Empty", "feeds" => []},
        {"title" => "Real", "feeds" => [{"feed_id" => 5}]}
      ]
    }
    migration = @user.account_migrations.create!(api_token: "token", fw_streams: fw_streams)

    assert_equal({5 => ["Real"]}, migration.streams)
  end

  test "streams returns nil when fw_streams is malformed" do
    migration = @user.account_migrations.create!(api_token: "token", fw_streams: nil)
    assert_nil migration.streams
  end
end
