require "test_helper"

class BackfillGuidTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = create_feeds(@user, 1).first
    @entry = @feed.entries.first
  end

  test "perform updates the guid column for entries on the feed" do
    @entry.update_columns(entry_id: "https://example.com/post-1", guid: nil)

    BackfillGuid.new.perform(@feed.id)

    # guid column is uuid; postgres reformats the md5 hex with dashes
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, @entry.reload.guid)
  end

  test "perform swallows ActiveRecord::RecordNotFound for missing feed" do
    assert_nothing_raised do
      BackfillGuid.new.perform(0)
    end
  end

  test "guid produces a stable MD5 for the same input" do
    @entry.update_columns(entry_id: "https://example.com/post-1")
    job = BackfillGuid.new
    job.instance_variable_set(:@feed, @feed)

    assert_equal job.guid(@entry.reload), job.guid(@entry.reload)
  end

  test "guid changes when entry_id changes" do
    job = BackfillGuid.new
    job.instance_variable_set(:@feed, @feed)

    @entry.update_columns(entry_id: "id-1")
    a = job.guid(@entry.reload)

    @entry.update_columns(entry_id: "id-2")
    b = job.guid(@entry.reload)

    refute_equal a, b
  end

  test "guid falls back to entry url or title when entry_id is nil" do
    @entry.update_columns(entry_id: nil, url: "https://example.com/fallback")
    job = BackfillGuid.new
    job.instance_variable_set(:@feed, @feed)

    a = job.guid(@entry.reload)
    refute_nil a

    @entry.update_columns(url: "https://example.com/different")
    b = job.guid(@entry.reload)
    refute_equal a, b
  end

  test "remove_protocol_and_host strips scheme and host" do
    job = BackfillGuid.new
    # URI#path/query don't include the ? separator, and #fragment drops the #
    result = job.remove_protocol_and_host(uri: "https://example.com/path?q=1#frag")
    assert_equal "/pathq=1frag", result
  end

  test "remove_protocol_and_host returns the original uri when there is no path/query/fragment" do
    job = BackfillGuid.new
    assert_equal "https://example.com", job.remove_protocol_and_host(uri: "https://example.com")
  end

  test "remove_protocol_and_host falls back to gsub on invalid URIs" do
    job = BackfillGuid.new
    result = job.remove_protocol_and_host(uri: "https://example com/path")
    assert_equal "//example com/path", result
  end
end
