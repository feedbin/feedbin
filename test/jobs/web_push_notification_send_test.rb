require "test_helper"

class WebPushNotificationSendTest < ActiveSupport::TestCase
  setup do
    @users = [users(:new), users(:ben)]
    @feeds = create_feeds(@users.first)
    @entries = @users.first.entries
  end

  test "should send push notification" do
    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:safari])
    }

    pool = PushServerMock.new("200")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    WebPushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_no_difference "Device.count" do
        assert_difference -> { pool.count }, +count do
          WebPushNotificationSend.new.perform(user_ids, @entries.first.id, false)
        end
      end
    end
  end

  test "should remove safari device" do
    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:safari])
    }

    pool = PushServerMock.new("410")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    WebPushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_difference "Device.count", -count do
        WebPushNotificationSend.new.perform(user_ids, @entries.first.id, false)
      end
    end
  end

  test "skip_read leaves out users who have already read the entry" do
    @users.each { |user| user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:safari]) }
    entry = @entries.first
    read_user, unread_user = @users
    UnreadEntry.where(entry_id: entry.id).delete_all
    UnreadEntry.create!(
      user: unread_user, entry: entry, feed_id: entry.feed_id,
      published: entry.published, entry_created_at: entry.created_at
    )

    pool = PushServerMock.new("200")
    WebPushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      WebPushNotificationSend.new.perform(@users.map(&:id), entry.id, true)
    end

    assert_equal 1, pool.count
    assert_nil pool.delivered["token#{read_user.id}"]
  end

  # A subscription title is the name one user gave the feed in their own
  # account. Reassigning the same local inside the loop hands it to every
  # later recipient who has no custom title of their own.
  test "one recipient's private title does not reach another's notification" do
    @users.each { |user| user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:safari]) }
    entry = @entries.first
    renamer, other = @users
    # Short enough that the notification's 36-byte truncation does not apply,
    # so the assertion below compares whole titles.
    entry.feed.update!(title: "The Feed's Own Name")
    Subscription.where(user_id: renamer.id, feed_id: entry.feed_id).update_all(title: "PRIVATE-RENAME")
    Subscription.where(user_id: other.id, feed_id: entry.feed_id).update_all(title: nil)

    pool = PushServerMock.new("200")
    WebPushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      WebPushNotificationSend.new.perform([renamer.id, other.id], entry.id, false)
    end

    assert_equal "PRIVATE-RENAME", pool.delivered["token#{renamer.id}"]
    assert_equal entry.feed.title, pool.delivered["token#{other.id}"]
  end

  test "should remove web device" do
    stub_request(:post, %r{example.com}).to_return(status: 410)

    # from https://github.com/pushpad/web-push/blob/master/spec/spec_helper.rb
    Feedbin::Application.config.vapid_key = WebPush::VapidKey.from_keys('BB37UCyc8LLX4PNQSe-04vSFvpUWGrENubUaslVFM_l5TxcGVMY0C3RXPeUJAQHKYlcOM2P4vTYmkoo0VZGZTM4=', 'OPrw1Sum3gRoL4-DXfSCC266r-qfFSRZrnj8MgIhRHg=')

    @devices = @users.map { |user|
      user.devices.create(
        token: "token#{user.id}",
        device_type: Device.device_types[:browser],
        data: {
          endpoint: 'https://example.com',
          keys: {
            p256dh: 'BN4GvZtEZiZuqFxSKVZfSfluwKBD7UxHNBmWkfiZfCtgDE8Bwh-_MtLXbBxTBAWH9r7IPKL0lhdcaqtL1dfxU5E=',
            auth: 'Q2BoAjC09xH3ywDLNJr-dA==',
          }
        }
      )
    }

    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    assert_difference -> {Device.count}, -count do
      WebPushNotificationSend.new.perform(user_ids, @entries.first.id, false)
    end
  end
end
