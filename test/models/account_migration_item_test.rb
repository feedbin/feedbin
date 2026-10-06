require "test_helper"

class AccountMigrationItemTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @migration = @user.account_migrations.create!(api_token: "tok")
  end

  test "creating an item enqueues one ImportFeed job with the item's id" do
    Sidekiq::Testing.fake! do
      AccountMigrator::ImportFeed.jobs.clear
      item = @migration.account_migration_items.create!

      assert_equal [[item.id]], AccountMigrator::ImportFeed.jobs.map { it["args"] }
    end
  end
end
