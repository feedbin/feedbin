require "test_helper"

# String#to_plain_text (config/initializers/core_ext/clean.rb) turns HTML into
# text. Most of what it is given is already text, which it answers without an
# HTML parse, and that answer has to be the one the parse would give.
class StringToPlainTextTest < ActiveSupport::TestCase
  test "text with nothing for an HTML parser to act on is not parsed" do
    Loofah.stub(:fragment, ->(*) { flunk "parsed plain text" }) do
      assert_equal "Daring Fireball: An Update", "Daring Fireball: An Update".to_plain_text
      assert_equal "leading, trailing and inner runs", "  leading,\ttrailing \r\n\n and   inner runs \n".to_plain_text
      assert_equal %(1 > 0, "quoted" 'single' 50% a;b #1), %(1 > 0, "quoted" 'single' 50% a;b #1).to_plain_text
      assert_equal "caf\u{E9} \u{4E2D}\u{6587} \u{1F600}", "caf\u{E9} \u{4E2D}\u{6587} \u{1F600}".to_plain_text
      assert_equal "", " \n\t ".to_plain_text
    end
  end

  test "only ASCII whitespace is collapsed and stripped" do
    assert_equal "\u{A0}no-break\u{A0}\u{A0}space\u{A0}", "\u{A0}no-break\u{A0}\u{A0}space\u{A0}".to_plain_text
    assert_equal "\u{3000}ideographic\u{2028}line\u{2029}", " \u{3000}ideographic\u{2028}line\u{2029} ".to_plain_text
    assert_equal "\u{FEFF}bom and\u{200B}zero width", "\u{FEFF}bom and\u{200B}zero width".to_plain_text
  end

  test "markup and character references are parsed" do
    assert_parsed "Bold & italic", "<b>Bold</b> &amp; <i>italic</i>"
    assert_parsed "AT&T", "AT&T"
    assert_parsed "1 < 2", "1 &lt; 2"
    assert_parsed "one two", "<p>one</p>\n<p>two</p>"
    assert_parsed "after", "<script>alert(1)</script>after"
  end

  test "characters the parser drops from text are still dropped" do
    assert_parsed "ab", "a\u{1}b"
    assert_parsed "ab", "a\u{8}b"
    assert_parsed "ab", "a\vb"
    assert_parsed "ab", "a\fb"
    assert_parsed "ab", "a\u{1F}b"
    assert_parsed "ab", "a\u{FFFE}b"
    assert_parsed "ab", "a\u{FFFF}b"
    assert_parsed "a b", "a\0b"
    assert_parsed "a\u{7F}b", "a\u{7F}b", parsed: false
  end

  test "invalid and non-UTF-8 strings are left to the parser" do
    # The parse raises on these bytes, and nothing here changes that.
    invalid = "caf\xE9".dup.force_encoding(Encoding::UTF_8)
    assert_raises(ArgumentError) { parse(invalid) }
    assert_raises(ArgumentError) { invalid.to_plain_text }

    assert_parsed "plain", "plain".encode(Encoding::ISO_8859_1)
    assert_parsed "plain", "plain".b
    assert_equal Encoding::UTF_8, "plain".b.to_plain_text.encoding
  end

  test "strings past the size the parser is known to keep whole are left to the parser" do
    assert_parsed "a" * 1.megabyte, "a" * 1.megabyte, parsed: false
    assert_parsed "a" * (1.megabyte + 1), "a" * (1.megabyte + 1)
  end

  test "the result is a new, unfrozen, UTF-8 String" do
    ["plain".freeze, "plain".html_safe, Class.new(String).new("plain"), "<b>plain</b>".freeze].each do |string|
      text = string.to_plain_text

      assert_equal "plain", text
      assert_instance_of String, text
      assert_not text.frozen?
      assert_not text.html_safe?
      assert_equal Encoding::UTF_8, text.encoding
      assert_not_same string, text
    end
  end

  test "agrees with the parse on every character, alone and in context" do
    codepoints = [*0x0..0x24F, 0x300, 0x2028, 0x2029, 0x3000, 0xFDD0, 0xFEFF, 0xFFFD, 0xFFFE, 0xFFFF, 0x1F600, 0x1FFFE, 0x10FFFF]
    strings = codepoints.flat_map do |codepoint|
      character = [codepoint].pack("U")
      [character, "#{character}a", "a#{character}", "a#{character}b", "a #{character}#{character} b"]
    end
    whitespace = [" ", "\t", "\n", "\r", "\r\n", "\n\n\n"]
    strings += whitespace.product(whitespace).flat_map { |a, b| ["#{a}one#{b}two#{a}", "#{a}#{b}"] }
    strings += ["", "amp;", "lt;b gt;", "#38;", "-->", "]]>", "a" * 5000, "a " * 5000, "a#{" " * 5000}b"]

    strings.each do |string|
      expected = parse(string)
      actual = string.to_plain_text

      assert_equal [expected, expected.encoding], [actual, actual.encoding], "for #{string.inspect}"
    end
  end

  private

  # What to_plain_text is without its short cut.
  def parse(string)
    Loofah.fragment(string)
      .scrub!(:prune)
      .to_text(encode_special_chars: false)
      .gsub(/\s+/, " ")
      .strip
  end

  def assert_parsed(expected, string, parsed: true)
    parses = 0
    fragment = Loofah.method(:fragment)
    text = Loofah.stub(:fragment, ->(*arguments) { parses += 1; fragment.call(*arguments) }) { string.to_plain_text }

    assert_equal expected, text
    assert_equal parsed, parses.positive?, "#{string[0, 40].inspect} was #{"not " if parsed}parsed"
  end
end
