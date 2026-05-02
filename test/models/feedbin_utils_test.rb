require "test_helper"

class FeedbinUtilsTest < ActiveSupport::TestCase
  setup do
    flush_redis
  end

  test "payment_details_key formats the redis key for a user" do
    assert_equal "payment_details:42:v5", FeedbinUtils.payment_details_key(42)
  end

  test "update_public_id_cache stores the content length under the public_id" do
    public_id = "pid-#{SecureRandom.hex(4)}"
    FeedbinUtils.update_public_id_cache(public_id, "abcde")

    stored = $redis[:refresher].with { |r| r.get(public_id) }
    assert_equal "5", stored
  end

  test "update_public_id_cache stores 0 when content is blank" do
    public_id = "pid-#{SecureRandom.hex(4)}"
    FeedbinUtils.update_public_id_cache(public_id, nil)

    assert_equal "0", $redis[:refresher].with { |r| r.get(public_id) }
  end

  test "update_public_id_cache also writes the alt key when provided" do
    pid     = "pid-#{SecureRandom.hex(4)}"
    pid_alt = "alt-#{SecureRandom.hex(4)}"
    FeedbinUtils.update_public_id_cache(pid, "hi", pid_alt)

    assert_equal "2", $redis[:refresher].with { |r| r.get(pid_alt) }
  end

  test "public_id_exists? returns whether the key is in redis" do
    pid = "pid-#{SecureRandom.hex(4)}"
    refute FeedbinUtils.public_id_exists?(pid)

    FeedbinUtils.update_public_id_cache(pid, "x")
    assert FeedbinUtils.public_id_exists?(pid)
  end

  test "shared_cache returns the redis hash with symbolized keys" do
    Sidekiq.redis { |r| r.hset("share-test", "a", "1", "b", "2") }
    assert_equal({a: "1", b: "2"}, FeedbinUtils.shared_cache("share-test"))
  end

  test "key_value_parser splits whitespace-separated key=value pairs" do
    result = FeedbinUtils.key_value_parser("a=1 b=2") { |v| v.to_i }
    assert_equal({"a" => 1, "b" => 2}, result)
  end

  test "key_value_parser handles nil string" do
    assert_equal({}, FeedbinUtils.key_value_parser(nil) { |v| v })
  end
end
