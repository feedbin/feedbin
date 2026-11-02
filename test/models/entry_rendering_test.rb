require "test_helper"

class EntryRenderingTest < ActiveSupport::TestCase
  setup do
    @feed = feeds(:daring_fireball)
  end

  def newsletter_feed
    feeds(:kottke).tap { it.update!(feed_type: :newsletter) }
  end

  test "encode and decode round-trip every version" do
    versions = {web: "<p>w</p>", api: "<p>a</p>", full: "<html>f</html>", diff: "<p><ins>d</ins></p>", extracted: %({"https://example.com/":"<p>e</p>"})}
    blob = EntryRendering.encode(versions, content: "<p>w</p>", crc: 7)
    assert_equal EntryRendering::LAYOUT, blob.getbyte(0)
    assert_equal 7, blob.byteslice(1, 4).unpack1("N")
    assert_equal versions, EntryRendering.decode(blob, content: "<p>w</p>")
  end

  test "decode tells an absent version from an empty one" do
    blob = EntryRendering.encode({web: "<p>w</p>", api: "", full: nil, diff: ""}, content: "<p>w</p>", crc: 0)
    decoded = EntryRendering.decode(blob, content: "<p>w</p>")
    assert_equal "", decoded[:api]
    assert_nil decoded[:full]
    assert_equal "", decoded[:diff]
    assert_equal Encoding::UTF_8, decoded[:web].encoding
  end

  test "encode and decode keep non-ASCII text" do
    versions = {web: "<p>café — ünïcode 😀</p>", api: "<p>日本語</p>"}
    blob = EntryRendering.encode(versions, content: "<p>café</p>", crc: 0)
    assert_equal versions.merge(full: nil, diff: nil, extracted: nil), EntryRendering.decode(blob, content: "<p>café</p>")
  end

  test "encode works without a dictionary when content is blank" do
    blob = EntryRendering.encode({web: "", api: ""}, content: "", crc: 0)
    assert_equal "", EntryRendering.decode(blob, content: "")[:web]
    blob = EntryRendering.encode({web: "", api: ""}, content: nil, crc: 0)
    assert_equal "", EntryRendering.decode(blob, content: nil)[:api]
  end

  test "decode rejects an unknown layout" do
    assert_raises(ArgumentError) { EntryRendering.decode([EntryRendering::LAYOUT + 1, 0].pack("CN"), content: "x") }
  end

  test "build renders web and api, and full only for newsletters" do
    entry = create_entry(@feed)
    rendering = EntryRendering.build(entry)
    assert_equal ContentFormatter.format!(entry.content, entry), rendering.web
    assert_equal ContentFormatter.api_format(entry.content, entry), rendering.api
    assert_nil rendering.full
    assert_nil rendering.diff
    assert_equal ContentFormatter::VERSION, rendering.version
  end

  test "build renders a diff when the original differs in length" do
    entry = create_entry(@feed)
    entry.update!(content: "<p>This is the new text.</p>", compressed_original_content: OriginalContent.compress("<p>This is the text.</p>", base: "<p>This is the new text.</p>"))
    assert_match %r{<ins>new\s*</ins>}, EntryRendering.build(entry).diff
  end

  test "build renders each saved page against its own URL and skips failed ones" do
    url = "https://example.com/story"
    page = {"url" => url, "result" => {"content" => %(<p><a href="/more">more</a><script>1</script></p>)}}
    entry = create_entry(@feed)
    entry.update!(data: {"saved_pages" => {url => page, "https://example.com/failed" => {"result" => nil}}})

    pages = EntryRendering.build(entry).extracted_pages

    assert_equal [url], pages.keys
    assert_includes pages[url], %(href="https://example.com/more")
    refute_includes pages[url], "<script"
  end

  test "build stores no extracted version without saved pages" do
    rendering = EntryRendering.build(create_entry(@feed))
    assert_nil rendering.extracted
    assert_equal({}, rendering.extracted_pages)
  end

  test "build renders full for a newsletter entry" do
    entry = create_entry(newsletter_feed)
    entry.update!(content: "<html><body><style>@media (max-width:480px){}</style><p>n</p></body></html>")
    assert_includes EntryRendering.build(entry).full, "max-width:10000px"
  end

  test "build renders a blank entry" do
    entry = create_entry(@feed)
    entry.update_columns(content: nil)
    rendering = EntryRendering.build(entry)
    assert_equal "", rendering.web
    assert_equal "", rendering.api
  end

  test "render! upserts and current_for? tracks the inputs" do
    entry = create_entry(@feed)
    rendering = EntryRendering.render!(entry)
    assert rendering.current_for?(entry)
    assert_equal 1, EntryRendering.where(entry_id: entry.id).count
    EntryRendering.render!(entry)
    assert_equal 1, EntryRendering.where(entry_id: entry.id).count
    entry.content = "<p>changed</p>"
    refute EntryRendering.find(entry.id).current_for?(entry)
  end

  test "a camo key change makes a stored rendering stale" do
    entry = create_entry(@feed)
    rendering = with_env("CAMO_HOST" => "https://example.com", "CAMO_KEY" => "one") { EntryRendering.render!(entry) }
    with_env("CAMO_HOST" => "https://example.com", "CAMO_KEY" => "one") { assert rendering.current_for?(entry) }
    with_env("CAMO_HOST" => "https://example.com", "CAMO_KEY" => "two") { refute rendering.current_for?(entry) }
  end

  test "current_for? is false for another VERSION" do
    entry = create_entry(@feed)
    rendering = EntryRendering.render!(entry)
    rendering.version = ContentFormatter::VERSION + 1
    refute rendering.current_for?(entry)
  end

  test "loading with_renderings stores missing and stale renderings in one insert" do
    current, missing, stale = 3.times.map { create_entry(@feed) }
    EntryRendering.render!(current)
    EntryRendering.where(entry_id: [missing.id, stale.id]).delete_all
    EntryRendering.render!(stale)
    EntryRendering.where(entry_id: stale.id).update_all(version: ContentFormatter::VERSION + 1)
    entries = Entry.where(id: [current.id, missing.id, stale.id]).with_renderings

    statements = capture_sql { entries.to_a }
    assert_equal 1, statements.count { it.start_with?(%(INSERT INTO "entry_renderings")) }

    statements = capture_sql { entries.each { it.rendering.web } }
    assert_empty statements.grep(/entry_renderings/)
    entries.each { assert EntryRendering.find(it.id).current_for?(it) }
  end

  test "with_renderings renders nothing until the relation loads" do
    entry = create_entry(@feed)
    EntryRendering.where(entry_id: entry.id).delete_all
    entries = Entry.where(id: entry.id).with_renderings
    statements = capture_sql { [entries.pluck(:id), entries.count, entries.exists?] }
    assert_empty statements.grep(/entry_renderings/)
    entries.load
    assert EntryRendering.exists?(entry.id)
  end

  test "loading with_renderings leaves out an entry that fails to render and stores the rest" do
    bad, good = 2.times.map { create_entry(@feed) }
    EntryRendering.where(entry_id: [bad.id, good.id]).delete_all
    entries = Entry.where(id: [bad.id, good.id]).with_renderings.order(:id)
    original = EntryRendering.method(:build)
    notified = []
    EntryRendering.stub(:build, ->(entry) { (entry.id == bad.id) ? raise("boom") : original.call(entry) }) do
      ErrorService.stub(:notify, ->(options) { notified << options }) do
        entries.load
      end
    end
    assert_equal [{error_class: "EntryRendering.prepare", entry_id: bad.id}], notified.map { {error_class: it[:error_class], entry_id: it[:parameters][:entry_id]} }
    assert EntryRendering.find(good.id).current_for?(good)
    assert_nil EntryRendering.find_by(entry_id: bad.id)
    assert_empty capture_sql { entries.last.rendering.web }.grep(/entry_renderings/)
  end

  test "loading with_renderings serves the renderings when storing them fails" do
    entry = create_entry(@feed)
    EntryRendering.where(entry_id: entry.id).delete_all
    entries = Entry.where(id: entry.id).with_renderings
    notified = []
    EntryRendering.stub(:upsert_all, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      ErrorService.stub(:notify, ->(options) { notified << options }) do
        entries.load
      end
    end
    assert_equal ["EntryRendering.prepare"], notified.map { it[:error_class] }
    statements = capture_sql { assert entries.first.rendering.web }
    assert_empty statements.grep(/entry_renderings/)
  end

  test "loading with_renderings writes in entry id order under a short lock timeout" do
    entries = 3.times.map { create_entry(@feed) }
    EntryRendering.where(entry_id: entries.map(&:id)).delete_all
    loaded = Entry.where(id: entries.map(&:id)).with_renderings.order(id: :desc)
    statements = capture_sql { loaded.to_a }
    insert = statements.find { it.start_with?(%(INSERT INTO "entry_renderings")) }
    written = insert.scan(/VALUES \((\d+)|\), \((\d+)/).flatten.compact.map(&:to_i)
    assert_equal entries.map(&:id).sort, written
    timeout = statements.index { it.match?(/SET LOCAL lock_timeout = '500ms'/) }
    assert timeout
    assert_operator timeout, :<, statements.index(insert)
  end

  test "store! writes under a short lock timeout" do
    entry = create_entry(@feed)
    statements = capture_sql { EntryRendering.render!(entry) }
    assert statements.any? { it.match?(/SET LOCAL lock_timeout = '500ms'/) }
  end
end
