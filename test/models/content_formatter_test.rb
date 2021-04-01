require "test_helper"

class ContentFormatterTest < ActiveSupport::TestCase
  setup do
    feed = feeds(:kottke)
    content = %(<p><a href="/link"><img src="/img.png"></a></p>)
    @entry = feed.entries.create!(content: content, public_id: SecureRandom.hex)
  end

  test "should format content" do
    expected = %(<p><a href="http://kottke.org/link"><img src="" data-camo-src="https://example.com/e3b56842cc257f75872facfb7febe44968bddf6a/687474703a2f2f6b6f74746b652e6f72672f696d672e706e67" data-canonical-src="http://kottke.org/img.png"></a></p>)
    assert_equal expected, ContentFormatter.format!(@entry.content, @entry)
  end

  test "should get absolute source" do
    expected = %(<p><a href="http://kottke.org/link"><img src="http://kottke.org/img.png"></a></p>)
    assert_equal expected, ContentFormatter.absolute_source(@entry.content, @entry)
  end

  test "should format for api" do
    expected = %(<p><a href="http://kottke.org/link"><img src="http://kottke.org/img.png"></a></p>)
    assert_equal expected, ContentFormatter.api_format(@entry.content, @entry)
  end

  test "should format for evernote" do
    expected = %(<p><a href="http://kottke.org/link"><img src="http://kottke.org/img.png"></a></p>)
    ContentFormatter.evernote_format(@entry.content, @entry)
  end

  test "should make summary" do
    content = %(<p>Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>)
    expected = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor"
    assert_equal expected, ContentFormatter.summary(content, 256)
  end

  test "should allow certain classes" do
    classes = %w[twitter-tweet instagram-media]
    classes.each do |css_class|
      content = %(<blockquote class="#{css_class}"></blockquote>)
      assert_equal content, ContentFormatter.format!(content)
    end
  end

  test "should not allow certain classes" do
    classes = %w[other-class]
    classes.each do |css_class|
      content = %(<blockquote class="#{css_class}"></blockquote>)
      assert_equal "<blockquote></blockquote>", ContentFormatter.format!(content)
    end
  end
end
