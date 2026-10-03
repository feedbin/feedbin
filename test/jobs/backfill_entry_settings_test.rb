require "test_helper"

class BackfillEntrySettingsTest < ActiveSupport::TestCase
  setup do
    @newsletter_feed = Feed.create!(feed_url: "https://example.com/?#{SecureRandom.hex}", feed_type: :newsletter)
    @other_feed = feeds(:daring_fireball)
  end

  test "a newsletter row keeps the sender, recipient and token, and loses the raw source and text" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter" => "From: News <news@example.com>", "newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com", "newsletter_token" => "t", "media_image" => "https://example.com/a.jpg"),
      data: object_form("newsletter_text" => "Hello", "type" => "newsletter", "format" => "html", "newsletter_to" => "t"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal "object", row[:type]
    assert_equal({"newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com", "newsletter_token" => "t"}, row[:settings])
    assert_equal({"type" => "newsletter", "format" => "html", "newsletter_to" => "t"}, row[:data])
  end

  test "a Mailgun-era row gets its sender from the payload, and the payload goes" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("archived_images" => true, "media_image" => "https://example.com/a.jpg"),
      data: object_form("newsletter_text" => "Hello", "type" => "newsletter", "format" => "html", "newsletter" => {"data" => {"from" => "Old <old@example.com>", "body-html" => "<p>Hello</p>"}}))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"archived_images" => true, "newsletter_from" => "Old <old@example.com>"}, row[:settings])
    assert_equal({"type" => "newsletter", "format" => "html"}, row[:data])
  end

  test "a Mailgun-era row with NULL settings gets settings with the sender" do
    entry = entry_with(@newsletter_feed,
      settings: nil,
      data: object_form("type" => "newsletter", "format" => "text", "newsletter" => {"data" => {"from" => "Old <old@example.com>"}}))

    run_backfill(entry)

    assert_equal({"newsletter_from" => "Old <old@example.com>"}, stored(entry)[:settings])
  end

  test "a sender already in settings is not replaced by the payload's" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter_from" => "Kept <kept@example.com>"),
      data: object_form("type" => "newsletter", "newsletter" => {"data" => {"from" => "Other <other@example.com>"}}))

    run_backfill(entry)

    assert_equal({"newsletter_from" => "Kept <kept@example.com>"}, stored(entry)[:settings])
  end

  test "a Mailgun-era row with no sender keeps NULL settings" do
    entry = entry_with(@newsletter_feed,
      settings: nil,
      data: object_form("type" => "newsletter", "newsletter" => {"data" => {"subject" => "Hi"}}))

    run_backfill(entry)

    row = stored(entry)
    assert_nil row[:settings]
    assert_equal({"type" => "newsletter"}, row[:data])
  end

  test "a NUL escape in the raw source goes through the Ruby path" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter" => "a\u0000b", "newsletter_from" => "News <news@example.com>", "newsletter_token" => "t"),
      data: object_form("newsletter_text" => "Hello", "type" => "newsletter"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal "object", row[:type]
    assert_equal({"newsletter_from" => "News <news@example.com>", "newsletter_token" => "t"}, row[:settings])
    assert_equal({"type" => "newsletter"}, row[:data])
  end

  test "a NUL escape in newsletter_text goes through the Ruby path" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter" => "From: News <news@example.com>", "newsletter_from" => "News <news@example.com>"),
      data: object_form("newsletter_text" => "a\u0000b", "type" => "newsletter", "format" => "text", "newsletter_to" => "t"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"newsletter_from" => "News <news@example.com>"}, row[:settings])
    assert_equal({"type" => "newsletter", "format" => "text", "newsletter_to" => "t"}, row[:data])
  end

  test "a NUL escape in the Mailgun payload still moves the sender into settings" do
    entry = entry_with(@newsletter_feed,
      settings: nil,
      data: object_form("type" => "newsletter", "newsletter" => {"data" => {"from" => "Old <old@example.com>", "body-plain" => "a\u0000b"}}))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"newsletter_from" => "Old <old@example.com>"}, row[:settings])
    assert_equal({"type" => "newsletter"}, row[:data])
  end

  test "a newsletter object row loses media_image and keeps newsletter_to" do
    entry = entry_with(@newsletter_feed,
      settings: object_form("newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com", "media_image" => "https://example.com/a.jpg"),
      data: object_form("type" => "newsletter", "format" => "html"))

    run_backfill(entry)

    assert_equal({"newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com"}, stored(entry)[:settings])
  end

  test "another row becomes an object without media_image, and its data does not change" do
    entry = entry_with(@other_feed,
      settings: string_form("embed_duration" => 647, "media_image" => "https://example.com/a.jpg"),
      data: object_form("enclosure_url" => "https://example.com/a.mp3"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal "object", row[:type]
    assert_equal({"embed_duration" => 647}, row[:settings])
    assert_equal({"enclosure_url" => "https://example.com/a.mp3"}, row[:data])
  end

  test "another row with nothing left becomes NULL" do
    media_only = entry_with(@other_feed, settings: string_form("media_image" => "https://example.com/a.jpg"), data: object_form({}))
    empty = entry_with(@other_feed, settings: string_form({}), data: object_form({}))

    run_backfill(media_only, empty)

    assert_nil stored(media_only)[:settings]
    assert_nil stored(empty)[:settings]
  end

  test "a NUL character in another row's settings goes, and its data does not change" do
    entry = entry_with(@other_feed,
      settings: string_form("media_image" => "x\u0000y", "embed_duration" => 5, "archived_images" => true),
      data: object_form("note" => "a\u0000b"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"embed_duration" => 5, "archived_images" => true}, row[:settings])
    assert_equal({"note" => "a\u0000b"}, row[:data])
  end

  test "another object row loses media_image" do
    entry = entry_with(@other_feed, settings: object_form("media_image" => "https://example.com/a.jpg", "archived_images" => true), data: object_form({}))

    run_backfill(entry)

    assert_equal({"archived_images" => true}, stored(entry)[:settings])
  end

  test "clean rows and NULL rows are not rewritten" do
    clean_newsletter = entry_with(@newsletter_feed, settings: object_form("newsletter_from" => "News <news@example.com>"), data: object_form("type" => "newsletter", "format" => "html"))
    clean_other = entry_with(@other_feed, settings: object_form("embed_duration" => 3), data: object_form({}))
    null_other = entry_with(@other_feed, settings: nil, data: object_form({}))
    before = [clean_newsletter, clean_other, null_other].map { stored(it)[:ctid] }

    run_backfill(clean_newsletter, clean_other, null_other)

    assert_equal before, [clean_newsletter, clean_other, null_other].map { stored(it)[:ctid] }
  end

  test "the backfill does not change updated_at" do
    entries = [
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "From: a", "newsletter_from" => "A <a@example.com>"), data: object_form("newsletter_text" => "Hello", "type" => "newsletter")),
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "a\u0000b"), data: object_form("type" => "newsletter")),
      entry_with(@other_feed, settings: string_form("embed_duration" => 647), data: object_form({}))
    ]
    before = entries.map { stored(it)[:updated_at] }

    run_backfill(*entries)

    assert_equal before, entries.map { stored(it)[:updated_at] }
  end

  # Sidekiq runs every job inside the Rails executor, where the query cache is
  # on, and exec_update does not clear it.
  test "a second run inside the query cache rewrites nothing" do
    entries = [
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "a\u0000b", "newsletter_from" => "N <n@example.com>"), data: object_form("type" => "newsletter")),
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "From: a", "newsletter_from" => "A <a@example.com>"), data: object_form("newsletter_text" => "Hello", "type" => "newsletter")),
      entry_with(@other_feed, settings: string_form("embed_duration" => 647), data: object_form({}))
    ]

    ActiveRecord::Base.cache do
      run_backfill(*entries)
      after_first = entries.map { stored(it)[:ctid] }

      run_backfill(*entries)

      assert_equal after_first, entries.map { stored(it)[:ctid] }
    end
  end

  test "build queues one job for each range of ids" do
    BackfillEntrySettings.jobs.clear
    entry_with(@other_feed, settings: nil, data: object_form({}))
    batches = (Entry.maximum(:id) / BackfillEntrySettings::BATCH_SIZE.to_f).ceil

    BackfillEntrySettings.new.build

    assert_equal batches, BackfillEntrySettings.jobs.size
    assert_equal [1], BackfillEntrySettings.jobs.first["args"]
    assert_equal [batches], BackfillEntrySettings.jobs.last["args"]
  end

  # Production cancels a statement after 15 s and an app write that waits on a
  # row lock after 10 s. A dense range of newsletter rows can exceed both, so
  # no statement may cover the whole 100,000-id range.
  test "no range statement covers more than 5,000 ids" do
    entry = entry_with(@newsletter_feed, settings: string_form("newsletter" => "From: a", "newsletter_from" => "A <a@example.com>"), data: object_form("type" => "newsletter"))
    spans = []
    record_span = ->(*, payload) do
      next unless ["BackfillEntrySettings newsletter", "BackfillEntrySettings other", "BackfillEntrySettings NUL rows"].include?(payload[:name])
      first, last = payload[:binds].first(2).map { it.respond_to?(:value) ? it.value : it }
      spans << last - first + 1
    end

    ActiveSupport::Notifications.subscribed(record_span, "sql.active_record") { run_backfill(entry) }

    assert_equal 60, spans.size
    assert_equal [5_000], spans.uniq
  end

  private

  # Writes settings and data exactly as a production row holds them.
  def entry_with(feed, settings:, data:)
    entry = feed.entries.create!(public_id: SecureRandom.hex, content: "<p>Body.</p>")
    Entry.connection.exec_update("UPDATE entries SET settings = $1::jsonb, data = $2::json WHERE id = $3", "entry_with", [settings, data, entry.id])
    entry
  end

  # Today's form: the hash as a JSON string inside jsonb.
  def string_form(hash)
    JSON.generate(JSON.generate(hash))
  end

  def object_form(hash)
    JSON.generate(hash)
  end

  def stored(entry)
    row = Entry.uncached do
      Entry.connection.select_one(
        "SELECT jsonb_typeof(settings) AS type, settings::text AS settings, data::text AS data, ctid::text AS ctid, updated_at::text AS updated_at FROM entries WHERE id = $1",
        "stored", [entry.id]
      )
    end
    settings = row["settings"] && JSON.parse(row["settings"])
    settings = JSON.parse(settings) if settings.is_a?(String)
    {type: row["type"], settings: settings, data: row["data"] && JSON.parse(row["data"]), ctid: row["ctid"], updated_at: row["updated_at"]}
  end

  # The entries of one test can straddle a range boundary, so run every range
  # they touch.
  def run_backfill(*entries)
    entries.map { (it.id - 1) / BackfillEntrySettings::BATCH_SIZE + 1 }.uniq.each { BackfillEntrySettings.new.perform(it) }
  end
end
