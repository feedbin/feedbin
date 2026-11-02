require "test_helper"

class Api::V3::StateChangeTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    UnreadEntry.where(user_id: @user.id).delete_all
    @a, @b = 2.times.map { |i| @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex) }
    @other = Feed.create!(feed_url: "https://other.example/feed").entries.create!(title: "x", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
  end

  test "marks read and unread, stars and unstars subscribed entries" do
    UnreadEntry.create_from_owners(@user, @a)

    result = change("mark_read" => [@a.id], "mark_unread" => [@b.id], "star" => [@b.id])

    assert_equal({"mark_read" => [@a.id], "mark_unread" => [@b.id], "star" => [@b.id]}, result[:applied])
    assert_equal [], result[:skipped]
    assert_equal [@b.id], unread_ids
    assert_equal [@b.id], starred_ids
    assert_equal "api", StarredEntry.find_by(user_id: @user.id, entry_id: @b.id).source
  end

  test "is idempotent and keeps request order without duplicates" do
    result = change("mark_unread" => [@b.id, @a.id, @b.id])
    assert_equal [@b.id, @a.id], result[:applied]["mark_unread"]

    change("mark_unread" => [@b.id, @a.id])
    assert_equal [@a.id, @b.id], unread_ids
  end

  test "skips entries the user cannot touch, once each" do
    result = change("mark_read" => [@other.id, @a.id], "star" => [@other.id, 999_999_999])

    assert_equal({"mark_read" => [@a.id], "star" => []}, result[:applied])
    assert_equal [{id: @other.id, reason: "not_subscribed"}, {id: 999_999_999, reason: "not_found"}], result[:skipped]
    assert_equal [], starred_ids
  end

  test "a starred entry from an unsubscribed feed can be unstarred" do
    StarredEntry.create_from_owners(@user, @other)

    result = change("unstar" => [@other.id])

    assert_equal [@other.id], result[:applied]["unstar"]
    assert_equal [], starred_ids
  end

  test "rejects an empty body, unknown verbs, scopes, too many ids, non-integers, and conflicts" do
    before = unread_ids
    assert_problem("", "missing") { change({}) }
    assert_problem("/read", "unknown") { change("read" => [1]) }
    assert_problem("/mark_read", "invalid_value") { change("mark_read" => {"feed_ids" => [1]}) }
    assert_problem("/mark_read", "too_many") { change("mark_read" => (1..1001).to_a) }
    assert_problem("/star", "invalid_value") { change("star" => ["a"]) }
    assert_problem("/star", "invalid_value") { change("star" => [0]) }
    assert_problem("/mark_unread", "conflict") { change("mark_read" => [1], "mark_unread" => [1]) }
    assert_problem("/unstar", "conflict") { change("star" => [1], "unstar" => [1]) }
    assert_equal before, unread_ids
  end

  private

  def unread_ids
    UnreadEntry.where(user_id: @user.id).order(:entry_id).pluck(:entry_id)
  end

  def starred_ids
    StarredEntry.where(user_id: @user.id).order(:entry_id).pluck(:entry_id)
  end

  def change(body)
    Api::V3::StateChange.new(@user, body).call
  end

  def assert_problem(pointer, code, &block)
    error = assert_raises(Api::V3::Problems::InvalidParameter, &block)
    assert_equal [pointer, code], [error.pointer, error.code]
  end
end
