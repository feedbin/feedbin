require "test_helper"

class OriginalContentTest < ActiveSupport::TestCase
  test "round trip returns the original as UTF-8" do
    base = "<p>Café ★ 日本語 with an added sentence.</p>"
    original = "<p>Café ★ 日本語.</p>"

    blob = OriginalContent.compress(original, base: base)
    result = OriginalContent.decompress(blob, base: base)

    assert_equal original, result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test "round trip uses the dictionary past 32 KB" do
    base = SecureRandom.alphanumeric(40_000)
    original = base[0, 20_000] + base[20_100..]

    blob = OriginalContent.compress(original, base: base)

    assert_operator blob.bytesize, :<, 200
    assert_equal original, OriginalContent.decompress(blob, base: base)
  end

  test "round trip works when the current content is much shorter than the original" do
    original = SecureRandom.alphanumeric(28_000)
    base = "<p>Removed</p>"

    blob = OriginalContent.compress(original, base: base)

    assert_equal original, OriginalContent.decompress(blob, base: base)
  end

  test "decompress returns nil when the base changed" do
    blob = OriginalContent.compress("<p>Old text.</p>", base: "<p>Old text and new text.</p>")

    assert_nil OriginalContent.decompress(blob, base: "<p>Old text and newer text.</p>")
  end

  test "decompress returns nil without a value or a base" do
    blob = OriginalContent.compress("<p>Old text.</p>", base: "<p>New text.</p>")

    assert_nil OriginalContent.decompress(nil, base: "<p>New text.</p>")
    assert_nil OriginalContent.decompress(blob, base: "")
    assert_nil OriginalContent.decompress(blob, base: nil)
  end

  test "compress returns nil without an original or a base" do
    assert_nil OriginalContent.compress("", base: "<p>New text.</p>")
    assert_nil OriginalContent.compress(nil, base: "<p>New text.</p>")
    assert_nil OriginalContent.compress("<p>Old text.</p>", base: "")
    assert_nil OriginalContent.compress("<p>Old text.</p>", base: nil)
  end

  test "decompress reports a damaged value and returns nil" do
    base = "<p>New text.</p>"
    blob = OriginalContent.compress("<p>Old text.</p>", base: base)
    damaged = blob.byteslice(0, 4) + "not a zstd frame".b
    notified = []

    ErrorService.stub(:notify, ->(options) { notified << options }) do
      assert_nil OriginalContent.decompress(damaged, base: base)
    end

    assert_equal ["OriginalContent#decompress"], notified.map { it[:error_class] }
  end
end
