require "test_helper"

class EntryRenderingTest < ActiveSupport::TestCase
  setup do
    @feed = feeds(:daring_fireball)
  end

  def newsletter_feed
    feeds(:kottke).tap { it.update!(feed_type: :newsletter) }
  end

  test "encode and decode round-trip all four versions" do
    versions = {web: "<p>w</p>", api: "<p>a</p>", full: "<html>f</html>", diff: "<p><ins>d</ins></p>"}
    blob = EntryRendering.encode(versions, content: "<p>w</p>", crc: 7)
    assert_equal 1, blob.getbyte(0)
    assert_equal 7, blob.byteslice(1, 4).unpack1("N")
    assert_equal versions, EntryRendering.decode(blob, content: "<p>w</p>")
  end

  test "decode returns nil for an absent full and diff" do
    blob = EntryRendering.encode({web: "<p>w</p>", api: "<p>a</p>"}, content: "<p>w</p>", crc: 0)
    decoded = EntryRendering.decode(blob, content: "<p>w</p>")
    assert_nil decoded[:full]
    assert_nil decoded[:diff]
    assert_equal Encoding::UTF_8, decoded[:web].encoding
  end

  test "encode and decode keep non-ASCII text" do
    versions = {web: "<p>café — ünïcode 😀</p>", api: "<p>日本語</p>"}
    blob = EntryRendering.encode(versions, content: "<p>café</p>", crc: 0)
    assert_equal versions.merge(full: nil, diff: nil), EntryRendering.decode(blob, content: "<p>café</p>")
  end

  test "encode works without a dictionary when content is blank" do
    blob = EntryRendering.encode({web: "", api: ""}, content: "", crc: 0)
    assert_equal "", EntryRendering.decode(blob, content: "")[:web]
    blob = EntryRendering.encode({web: "", api: ""}, content: nil, crc: 0)
    assert_equal "", EntryRendering.decode(blob, content: nil)[:api]
  end

  test "decode rejects an unknown layout" do
    assert_raises(ArgumentError) { EntryRendering.decode("\x02\x00\x00\x00\x00".b, content: "x") }
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

  test "source_html wraps text entries and youtube entries" do
    entry = create_entry(@feed)
    entry.data = {"format" => "text"}
    entry.content = "line one\nline two"
    assert_equal ContentFormatter.text_email(entry.content), EntryRendering.source_html(entry)
    entry.data = {"youtube_video_id" => "abc"}
    assert_includes EntryRendering.source_html(entry), %(<iframe src="https://www.youtube.com/embed/abc?rel=0)
  end

  test "source_html keeps a youtube description as markup" do
    entry = create_entry(@feed)
    entry.data = {"youtube_video_id" => "abc"}
    entry.content = "line one"
    html = EntryRendering.source_html(entry)
    assert_includes html, "<p>line one</p>"
    refute_kind_of ActiveSupport::SafeBuffer, html
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
end
