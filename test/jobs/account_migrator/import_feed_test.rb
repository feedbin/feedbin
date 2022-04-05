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
      stub_request_file("atom.xml", @item.fw_feed&.dig("feed_url"))
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

    test "API error should mark as failed" do
      stub_request_file("atom.xml", @item.fw_feed&.dig("feed_url"))
      stub_request_file("migration_error_response.json", /#{ENV['ACCOUNT_HOST']}\/api\/v2\/feed_items\/list/,
        headers: {
          "Content-Type" => "application/json; charset=utf-8"
        }
      )
      AccountMigrator::ImportFeed.new.perform(@item.id)
      assert @item.reload.failed?, "Import should have failed"
    end

  end
end