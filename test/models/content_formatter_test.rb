require "test_helper"

class ContentFormatterTest < ActiveSupport::TestCase
  setup do
    feed = feeds(:kottke)
    content = %(<p><a href="/link"><img src="/img.png"></a></p>)
    @entry = feed.entries.create!(content: content, public_id: SecureRandom.hex)
  end

  test "should format content" do
    expected = %(<p><a href="http://kottke.org/link"><img data-camo-src="https://example.com/e3b56842cc257f75872facfb7febe44968bddf6a/687474703a2f2f6b6f74746b652e6f72672f696d672e706e67" data-canonical-src="http://kottke.org/img.png"></a></p>)
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
    result = ContentFormatter.evernote_format(@entry.content, @entry)
    assert_includes result, "http://kottke.org/link"
    assert_includes result, "http://kottke.org/img.png"
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
      assert_equal '<blockquote></blockquote>', ContentFormatter.format!(content)
    end
  end

  test "should replace unknown dashed elemnents" do
    content = <<~EOD
    <math>
      <annotation-xml></annotation-xml>
    </math>
    <custom-element>Hello</custom-element>
    EOD

    expected = <<~EOD
    <math>
      <annotation-xml></annotation-xml>
    </math>
    <span>Hello</span>
    EOD
    assert_equal expected, ContentFormatter.format!(content)
  end

  test "newsletter_format sanitizes through HTML::Pipeline" do
    content = %(<p>Hello <script>alert(1)</script> world</p>)
    result = ContentFormatter.newsletter_format(content)
    assert_includes result, "Hello"
    assert_includes result, "world"
    refute_includes result, "<script"
  end

  test "newsletter_format applies camo proxying when configured" do
    content = %(<p><img src="http://example.com/img.png"></p>)
    with_env("CAMO_HOST" => "https://example.com", "CAMO_KEY" => "secret") do
      result = ContentFormatter.newsletter_format(content)
      assert_includes result, "data-camo-src"
    end
  end

  test "format! uses newsletter scrub_mode for newsletter feeds" do
    feed = Feed.create!(feed_url: "newsletter://x@example.com", host: "newsletters.feedbin.com", title: "NL", feed_type: :newsletter)
    entry = feed.entries.create!(content: "<p>Hi</p>", public_id: SecureRandom.hex)
    assert feed.newsletter?, "expected newsletter feed"
    refute_nil ContentFormatter.format!(entry.content, entry)
  end

  test "format! adds substack filter when entry is from substack" do
    @entry.newsletter_from = "writer@substack.com"
    @entry.save!
    @entry.reload
    content = %(<div class="body markup"><p>Hello</p></div>)
    result = ContentFormatter.format!(content, @entry)
    refute_nil result
  end

  test "format! invokes ImageFallback when entry has archived_images" do
    @entry.archived_images = {"http://kottke.org/img.png" => "https://archive/x.png"}
    @entry.save!
    @entry.reload
    assert @entry.archived_images?, "expected archived_images? true"
    ImageFallback.stub :new, ->(html) { OpenStruct.new(add_fallbacks: html) } do
      result = ContentFormatter.format!(@entry.content, @entry)
      refute_nil result
    end
  end

  test "format! accepts an explicit base_url instead of an entry" do
    content = %(<p><a href="/link"><img src="/img.png"></a></p>)
    result = ContentFormatter.format!(content, nil, false, "http://override.example/")
    assert_includes result, "http://override.example/link"
  end

  test "absolute_source returns original content when an exception is raised" do
    content = %(<p>fine</p>)
    HTML::Pipeline.stub :new, ->(*) { raise "boom" } do
      assert_equal content, ContentFormatter.absolute_source(content, @entry)
    end
  end

  test "api_format uses newsletter scrub_mode for newsletter feeds" do
    feed = Feed.create!(feed_url: "newsletter://y@example.com", host: "newsletters.feedbin.com", title: "NL2")
    entry = feed.entries.create!(content: "<p>Hi</p>", public_id: SecureRandom.hex)
    refute_nil ContentFormatter.api_format(entry.content, entry)
  end

  test "api_format returns original content when an exception is raised" do
    content = %(<p>fine</p>)
    HTML::Pipeline.stub :new, ->(*) { raise "boom" } do
      assert_equal content, ContentFormatter.api_format(content, @entry)
    end
  end

  test "app_format produces output and falls back to original content on error" do
    content = %(<p><a href="/link"><img src="/img.png"></a></p>)
    result = ContentFormatter.app_format(content, @entry)
    assert_includes result, "http://kottke.org/link"

    HTML::Pipeline.stub :new, ->(*) { raise "boom" } do
      assert_equal content, ContentFormatter.app_format(content, @entry)
    end
  end

  test "evernote_format returns original content when an exception is raised" do
    content = %(<p>fine</p>)
    HTML::Pipeline.stub :new, ->(*) { raise "boom" } do
      assert_equal content, ContentFormatter.evernote_format(content, @entry)
    end
  end

  test "summary returns empty string for nil content" do
    assert_equal "", ContentFormatter.summary(nil)
  end

  test "summary returns empty string when InvalidDocumentException is raised" do
    HTML::Pipeline.stub :new, ->(*) { raise HTML::Pipeline::Filter::InvalidDocumentException.new("bad") } do
      assert_equal "", ContentFormatter.summary("<p>x</p>", 10)
    end
  end

  test "text_email renders markdown and falls back to original content on error" do
    out = ContentFormatter.text_email("# Hello\n\nworld")
    assert_includes out, "Hello"
    assert_includes out, "world"

    Redcarpet::Markdown.stub :new, ->(*) { raise "boom" } do
      assert_equal "raw", ContentFormatter.text_email("raw")
    end
  end

  test "document falls back to html4_fragment for deeply nested HTML" do
    Loofah.stub :html5_fragment, ->(*) { raise "Document tree depth limit exceeded" } do
      Loofah.stub :html4_fragment, ->(_) { :ok } do
        assert_equal :ok, ContentFormatter.document("<div><div></div></div>")
      end
    end
  end

  test "document re-raises unrelated exceptions" do
    Loofah.stub :html5_fragment, ->(*) { raise "something else" } do
      assert_raises(RuntimeError) { ContentFormatter.document("<p>x</p>") }
    end
  end

  private

  def with_env(values)
    originals = {}
    values.each do |k, v|
      originals[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    originals.each { |k, v| ENV[k] = v }
  end
end
