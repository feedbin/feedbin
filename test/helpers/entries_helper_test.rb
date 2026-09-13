require "test_helper"

class EntriesHelperTest < ActiveSupport::TestCase
  setup do
    @entry = create_entry(Feed.first)
  end

  # The version element is the only lever that invalidates every cached entry
  # fragment at once. The favicon cutover bumped it: fragments rendered under
  # the old code digested the favicons row, and the element is the images row
  # now.
  test "entries_cache_key digests the rows the partial renders and ends in the version" do
    key = EntriesHelper.entries_cache_key(@entry, {})

    assert_equal @entry, key.first
    assert_equal "v15", key.last
    assert_equal 7, key.size
  end

  test "api_entries_cache_key carries the content-diff flag, the entry, and its own version" do
    assert_equal [true, @entry, "v2"], EntriesHelper.api_entries_cache_key(@entry, true)
    assert_equal [false, @entry, "v2"], EntriesHelper.api_entries_cache_key(@entry, false)
  end

  test "the entries key digests the entry icon row" do
    entry = create_entry(feeds(:daring_fireball))
    before = EntriesHelper.entries_cache_key(Entry.find(entry.id))
    create_image_row(provider: :entry_icon, provider_id: entry.id.to_s, feed_id: entry.feed_id, kind: :avatar, variant: "200x200")

    assert_not_equal before, EntriesHelper.entries_cache_key(Entry.find(entry.id))
  end
end
