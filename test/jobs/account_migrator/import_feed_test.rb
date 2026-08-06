require "test_helper"
module AccountMigrator
  class ImportFeedTest < ActiveSupport::TestCase
    setup do
      @user = users(:new)
      @token = "token"
      @migration = @user.account_migrations.create!(api_token: @token, fw_streams: load_support_json("migration_streams_response"))

      @item = @migration.account_migration_items.create!(fw_feed: {
        title: "Daring Fireball",
        feed_id: 290,
        feed_url: "http://daringfireball.net/index.xml"
      })
    end

    test "should import feed" do
      stub_request_file("atom.xml", @item.fw_feed&.safe_dig("feed_url"))
      stub_request_file("migration_ids_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list.*?offset=0.*?read=false/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      stub_request_file("migration_starred_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list.*?offset=0.*?starred=true/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      stub_request_file("migration_empty_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list.*?offset=100/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      assert_difference("@user.starred_entries.count", +2) do
        assert_difference("@user.unread_entries.count", +4) do
          assert_difference("Feed.count", +1) do
            AccountMigrator::ImportFeed.new.perform(@item.id)
          end
        end
      end

      assert @migration.reload.complete?, "Migration should be complete"
      assert @item.reload.complete?, "Migration item should be complete"
      assert_equal "Matched 2 of 2 starred articles. Matched 4 of 4 unread articles. ", @item.reload.message
      assert_equal ["Favorites", "Videos"], @user.feed_tags.map(&:name)
    end

    test "should maintain the starred entries counter cache" do
      stub_feed_items

      AccountMigrator::ImportFeed.new.perform(@item.id)

      entries = @user.starred_entries.map { _1.entry }
      assert_equal 2, entries.count
      assert_equal [1, 1], entries.map { _1.reload.starred_entries_count },
        "EntryDeleter uses starred_entries_count as its delete guard, so imported stars must maintain it"
  end

    test "a feed that cannot be found still finishes the migration" do
      stub_request(:get, @item.fw_feed&.safe_dig("feed_url")).to_return(status: 404, body: "")
      stub_request_file("migration_empty_response.json", /#{ENV["ACCOUNT_HOST"]}\/api\/v2\/feed_items\/list/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )

      AccountMigrator::ImportFeed.new.perform(@item.id)

      assert @item.reload.failed?, "the item should be marked failed"
      assert @migration.reload.complete?, "a migration with nothing left pending must not stay in processing"
    end

    test "an unexpected failure still finishes the migration" do
      stub_request_file("atom.xml", @item.fw_feed&.safe_dig("feed_url"))
      stub_request_file("migration_empty_response.json", /#{ENV["ACCOUNT_HOST"]}\/api\/v2\/feed_items\/list/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )

      AccountMigrator::ImportFeed.stub_any_instance(:import_starred, -> (*) { raise "boom" }) do
        assert_raises(RuntimeError) do
          AccountMigrator::ImportFeed.new.perform(@item.id)
        end
      end

      assert @item.reload.failed?, "the item should be marked failed"
      assert @migration.reload.complete?, "a migration with nothing left pending must not stay in processing"
    end

    test "API error should mark as failed" do
      stub_request_file("atom.xml", @item.fw_feed&.safe_dig("feed_url"))
      stub_request_file("migration_error_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      AccountMigrator::ImportFeed.new.perform(@item.id)
      assert @item.reload.failed?, "Import should have failed"
    end

    private

    def stub_feed_items
      stub_request_file("atom.xml", @item.fw_feed&.safe_dig("feed_url"))
      stub_request_file("migration_ids_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list.*?offset=0.*?read=false/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      stub_request_file("migration_starred_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list.*?offset=0.*?starred=true/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      stub_request_file("migration_empty_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list.*?offset=100/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
    end
  end
end