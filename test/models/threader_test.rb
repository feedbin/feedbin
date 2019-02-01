require "test_helper"

class ThreaderTest < ActiveSupport::TestCase
  setup do
    user = users(:ben)
    @feed = user.feeds.first
    @parent_entry = @feed.entries.create!(threaded_entry)
  end

  test "should add thread" do
    entry_hash = threaded_entry(@parent_entry.thread_id)

    UnreadEntry.where(entry: @parent_entry).delete_all

    threader = Threader.new(entry_hash, @feed)
    assert_difference "UpdatedEntry.count", +1 do
      assert(threader.thread)
    end

    assert_equal(@parent_entry.reload.thread_id, entry_hash["thread_id"])
    assert_equal(@parent_entry.reload.thread.length, 1)
  end

  test "should not create more than one entry" do
    reply_one = threaded_entry(@parent_entry.thread_id)
    reply_two = threaded_entry(reply_one["thread_id"])

    Threader.new(reply_one, @feed).thread
    Threader.new(reply_two, @feed).thread

    assert FeedbinUtils.public_id_exists?(reply_two["public_id"]), "reply_two should have a public_id saved"
    assert_equal(2, @parent_entry.reload.data["thread"].length)
  end

  def threaded_entry(reply_to = nil)
    thread_id = Random.new.rand(10000)
    data = {
      "tweet" => {
        "id" => thread_id,
        "user" => {
          "screen_name" => "bsaid",
        },
      },
    }
    if reply_to
      data["tweet"]["in_reply_to_status_id"] = reply_to
    end
    {
      "thread_id" => thread_id,
      "public_id" => SecureRandom.hex,
      "content" => "<p>#{Faker::Lorem.paragraph}</p>",
      "data" => data,
    }
  end
end
