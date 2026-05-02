require "test_helper"

class AccountMigrationItemTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @migration = @user.account_migrations.create!(api_token: "tok")
  end

  test "creating an item enqueues an ImportFeed job" do
    Sidekiq::Testing.fake! do
      AccountMigrator::ImportFeed.jobs.clear

      assert_difference -> { AccountMigrator::ImportFeed.jobs.size }, +1 do
        @migration.account_migration_items.create!
      end
    end
  end

  test "passes the new item's id to the ImportFeed job" do
    Sidekiq::Testing.fake! do
      AccountMigrator::ImportFeed.jobs.clear
      item = @migration.account_migration_items.create!

      assert_equal [item.id], AccountMigrator::ImportFeed.jobs.last["args"]
    end
  end

  test "fw_feed accessor reads and writes through data" do
    Sidekiq::Testing.fake! do
      item = @migration.account_migration_items.create!(fw_feed: {"feed_id" => 42, "title" => "test"})
      assert_equal({"feed_id" => 42, "title" => "test"}, item.fw_feed)
    end
  end
end
