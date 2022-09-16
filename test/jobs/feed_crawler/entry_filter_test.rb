require "test_helper"

class EntryFilterTest < ActiveSupport::TestCase
  setup do
    @feed = Feed.first
  end

  def test_should_get_new_entries
    entries = sample_entries
    filter = EntryFilter.new(entries)
    results = filter.filter
    assert_equal entries.length, results.length
    assert_equal({new: 1}, filter.stats)
    results.each do |entry|
      assert_nil entry[:update]
    end
  end

  def test_should_get_updated_entries
    entries = sample_entries
    $redis[:refresher].with do |connection|
      entries.each do |entry|
        data = entry.to_entry
        data[:fingerprint] = SecureRandom.hex
        @feed.entries.create!(data)
        connection.set(entry.public_id, 1000)
      end
    end

    filter = EntryFilter.new(entries)
    results = filter.filter

    assert_equal entries.length, results.length
    assert_equal({updated: 1}, filter.stats)
  end

  def test_should_ignore_old_updated_entries
    entries = [
      sample_entries(published: 23.hours.ago),
      sample_entries(published: 25.hours.ago)
    ].flatten

    $redis[:refresher].with do |connection|
      entries.each do |entry|
        data = entry.to_entry
        data[:fingerprint] = SecureRandom.hex
        @feed.entries.create!(data)
      end
    end

    filter = EntryFilter.new(entries, check_for_changes: false, always_check_recent: true)
    results = filter.filter
    assert_equal({updated: 1, unchanged: 1}, filter.stats)
  end

  def test_should_ignore_updated_entries
    entries = sample_entries
    $redis[:refresher].with do |connection|
      entries.each do |entry|
        data = entry.to_entry
        data[:fingerprint] = SecureRandom.hex
        @feed.entries.create!(data)
      end
    end

    results = EntryFilter.filter!(entries, check_for_changes: false)
    assert_equal 0, results.length
  end

  def test_should_ignore_existing_entries_database
    entries = sample_entries
    $redis[:refresher].with do |connection|
      entries.each do |entry|
        @feed.entries.create!(entry.to_entry)
      end
    end

    results = EntryFilter.filter!(entries)
    assert_equal 0, results.length
  end

  def test_should_ignore_existing_entries_cache
    entries = sample_entries
    $redis[:refresher].with do |connection|
      entries.each do |entry|
        connection.set(entry.public_id, entry.content.length)
      end
    end

    results = EntryFilter.filter!(entries)
    assert_equal 0, results.length
  end

  def test_should_ignore_old_entries
    entries = [
      sample_entries,
      sample_entries(published: (Date.today - 3).to_time),
      sample_entries(published: nil),
    ].flatten
    filter = EntryFilter.new(entries, date_filter: (Date.today - 2).to_time, check_for_changes: false)
    results = filter.filter
    assert_equal 2, results.length
    assert_equal({new: 2, unchanged: 1}, filter.stats)
  end

  private

  def sample_entries(published: Time.now)
    data = {
      public_id: SecureRandom.hex,
      content: SecureRandom.hex,
      published: published,
      fingerprint: SecureRandom.hex,
    }
    data[:to_entry] = data.clone
    [OpenStruct.new(data)]
  end
end
