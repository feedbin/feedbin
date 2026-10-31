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
    expected = %(<p><a href="http://kottke.org/link"><img src="http://kottke.org/img.png" data-camo-src="https://example.com/e3b56842cc257f75872facfb7febe44968bddf6a/687474703a2f2f6b6f74746b652e6f72672f696d672e706e67"></a></p>)
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
    <svg><foo-bar></foo-bar></svg>
    <custom-element>Hello</custom-element>
    <div><nested-element>Inner</nested-element></div>
    EOD

    expected = <<~EOD
    <math>
      <annotation-xml></annotation-xml>
    </math>
    <svg></svg>
    <span>Hello</span>
    <div><span>Inner</span></div>
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

  test "api_format keeps src and adds data-camo-src" do
    with_env("CAMO_HOST" => "https://example.com", "CAMO_KEY" => "secret") do
      result = ContentFormatter.api_format(%(<img src="http://kottke.org/img.png">), @entry)
      assert_includes result, %( src="http://kottke.org/img.png")
      assert_match %r{data-camo-src="https://example.com/\h{40}/\h+"}, result
      refute_includes result, "data-canonical-src"
    end
  end

  test "api_format output is unchanged without camo" do
    with_env("CAMO_HOST" => nil, "CAMO_KEY" => nil) do
      assert_equal %(<img src="http://kottke.org/img.png">), ContentFormatter.api_format(%(<img src="http://kottke.org/img.png">), @entry)
    end
  end

  test "newsletter_format widens max-width media queries of 400px and up" do
    input = "<style>@media screen and (max-width:480px) { .a {} } @media (max-width:320px) { .b {} }</style><p>x</p>"
    result = ContentFormatter.newsletter_format(input)
    assert_includes result, "(max-width:10000px)"
    assert_includes result, "(max-width:320px)"
  end

  test "Full.media_queries leaves a non-numeric width alone" do
    assert_equal "@media (max-width:abcpx) {", ContentFormatter::Full.media_queries("@media (max-width:abcpx) {")
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
    entry = feed.entries.create!(content: "<table><tr><td>Hi</td></tr></table>", public_id: SecureRandom.hex)
    assert feed.newsletter?, "expected newsletter feed"
    result = ContentFormatter.format!(entry.content, entry)
    refute_includes result, "<table"
    refute_includes result, "<td"
    assert_includes result, "Hi"
  end

  test "format! adds substack filter when entry is from substack" do
    @entry.newsletter_from = "writer@substack.com"
    @entry.save!
    @entry.reload
    content = %(<div class="body markup"><p>Hello</p></div><div><p>ignore</p></div>)
    result = ContentFormatter.format!(content, @entry)
    assert_includes result, "Hello"
    refute_includes result, "ignore"
  end

  test "every stored format renders from the entry alone" do
    ContentFormatter::FORMATS.each_key do |format|
      result = ContentFormatter.render(format, @entry.content, entry: @entry)
      assert_includes result, "img", format.to_s
    end
  end

  test "render matches the named entry points" do
    assert_equal ContentFormatter.format!(@entry.content, @entry), ContentFormatter.render(:web, @entry.content, entry: @entry)
    assert_equal ContentFormatter.api_format(@entry.content, @entry), ContentFormatter.render(:api, @entry.content, entry: @entry)
    assert_equal ContentFormatter.newsletter_format(@entry.content), ContentFormatter.render(:full, @entry.content)
  end

  test "shared sanitize configs are frozen" do
    assert ContentFormatter::ALLOWLIST_DEFAULT.frozen?
    assert ContentFormatter::ALLOWLIST_DEFAULT[:elements].frozen?
    assert ContentFormatter::ALLOWLIST_EVERNOTE[:attributes].frozen?
  end

  # Scrub#prune replaces doc.scrub!(:prune) for speed, so it has to make the
  # same decisions as Loofah on everything prune handles.
  test "Scrub#prune matches Loofah's prune" do
    [
      %(<p>a<!-- c -->b</p><!-- top -->),
      %(<p>keep</p><script>alert(1)</script><style>p{}</style><object><p>inner</p></object>),
      %(<div><unknown-tag><p>lost</p></unknown-tag>after</div>),
      %(<a href="javascript:alert(1)">x</a><a href="http://e.com/a b">y</a><img src="data:text/html,x" alt=" ">),
      %(<svg viewBox="0 0 1 1"><![CDATA[x<y]]><use href="#a" xlink:href="http://e.com"/></svg>),
      %(<math><![CDATA[a&b]]><mi>x</mi></math>),
      %(<p id="i" class="c" onclick="x()" data-x="1" title="">t</p>),
      %(<table><tr><td align="left">c</td></tr></table>)
    ].each do |html|
      expected = ContentFormatter.document(html).scrub!(:prune).to_s
      doc = ContentFormatter.document(html)
      ContentFilters::Scrub.new(doc, {}).prune
      assert_equal expected, doc.to_s, html
    end
  end

  test "format! marks Ghost bookmark cards as system content" do
    result = ContentFormatter.format!(%(<div class="kg-bookmark-card">c</div><p><a class="kg-bookmark-card other">x</a></p>))
    assert_equal 2, result.scan("kg-bookmark-card system-content").size
  end

  test "format! removes the expand control inside a figure" do
    result = ContentFormatter.format!(%(<figure><a class="image-link-expand"><svg><path></path></svg></a><svg></svg></figure>))
    assert_equal %(<figure><a></a><svg></svg></figure>), result
  end

  test "format! accepts an explicit base_url instead of an entry" do
    content = %(<p><a href="/link"><img src="/img.png"></a></p>)
    result = ContentFormatter.format!(content, nil, "http://override.example/")
    assert_includes result, "http://override.example/link"
  end

  test "absolute_source returns original content when an exception is raised" do
    content = %(<p>fine</p>)
    HTML::Pipeline.stub :new, ->(*) { raise "boom" } do
      assert_equal content, ContentFormatter.absolute_source(content, @entry)
    end
  end

  test "api_format uses newsletter scrub_mode for newsletter feeds" do
    feed = Feed.create!(feed_url: "newsletter://y@example.com", host: "newsletters.feedbin.com", title: "NL2", feed_type: :newsletter)
    entry = feed.entries.create!(content: "<table><tr><td>Hi</td></tr></table>", public_id: SecureRandom.hex)
    result = ContentFormatter.api_format(entry.content, entry)
    refute_includes result, "<table"
    refute_includes result, "<td"
    assert_includes result, "Hi"
  end

  test "api_format accepts a base_url instead of an entry" do
    content = %(<p><a href="/link"><img src="/img.png"></a><script>1</script></p>)
    result = ContentFormatter.api_format(content, nil, "http://override.example/")
    assert_includes result, %(href="http://override.example/link")
    assert_includes result, %(src="http://override.example/img.png")
    refute_includes result, "<script"
  end

  test "api_format returns original content when an exception is raised" do
    content = %(<p>fine</p>)
    HTML::Pipeline.stub :new, ->(*) { raise "boom" } do
      assert_equal content, ContentFormatter.api_format(content, @entry)
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

  test "document parses an element past the default attribute limit" do
    html = "<div " + Array.new(500) { |i| %(a#{i}="x") }.join(" ") + ">many attributes</div>"
    assert_includes ContentFormatter.document(html).to_html, "many attributes"
  end

  test "html_document keeps an element past the default attribute limit" do
    html = "<div " + Array.new(500) { |i| %(a#{i}="x") }.join(" ") + ">many attributes</div>"
    document = ContentFormatter.html_document(html)
    assert_kind_of Nokogiri::HTML5::Document, document
    assert_equal 500, document.at("div").attributes.size
  end

  test "html_document falls back to HTML4 past the raised attribute limit" do
    html = "<div " + Array.new(ContentFormatter::HTML5_MAX_ATTRIBUTES + 1) { |i| %(a#{i}="x") }.join(" ") + ">many attributes</div>"
    document = ContentFormatter.html_document(html)
    assert_kind_of Nokogiri::HTML4::Document, document
    assert_includes document.to_html, "many attributes"
  end

  test "document re-raises unrelated exceptions" do
    Loofah.stub :html5_fragment, ->(*) { raise "something else" } do
      assert_raises(RuntimeError) { ContentFormatter.document("<p>x</p>") }
    end
  end

  # 018 — Feedbin's client dispatches on data attributes, so content from a feed
  # must not be able to supply them.
  test "format! strips data attributes that came from the content" do
    payload = %(<div data-behavior="iframe_placeholder" data-iframe-src="javascript:alert(1)" data-iframe-embed-url="https://evil.example/x.js" data-controller="embed-player" data-action="click-&gt;embed-player#showPlayer">Load embed</div>)

    result = ContentFormatter.format!(payload)

    %w[data-behavior data-iframe-src data-iframe-embed-url data-controller data-action].each do |attribute|
      refute_includes result, attribute
    end
  end

  test "api_format strips data attributes that came from the content" do
    payload = %(<div data-behavior="iframe_placeholder">x</div>)

    refute_includes ContentFormatter.api_format(payload, @entry), "data-behavior"
  end

  # The camo and iframe filters run after the attribute filter, so the ones
  # Feedbin injects itself have to survive. "should format content" covers camo;
  # this covers the ordering explicitly.
  test "format! keeps the data attributes Feedbin injects downstream" do
    result = ContentFormatter.format!(@entry.content, @entry)

    assert_includes result, "data-canonical-src"
  end

  # 044 — the allowlist admits these attributes but named no protocols for them.
  test "text_email refuses a javascript iframe src" do
    result = ContentFormatter.text_email(%(<iframe src="javascript:alert(document.domain)"></iframe>))

    refute_includes result, "javascript:"
  end

  test "text_email refuses javascript in the other url-bearing attributes" do
    {
      %(<source src="javascript:alert(1)">) => "source src",
      %(<video src="javascript:alert(1)" poster="javascript:alert(2)"></video>) => "video src and poster",
      %(<audio src="javascript:alert(1)"></audio>) => "audio src"
    }.each do |payload, description|
      refute_includes ContentFormatter.text_email(payload), "javascript:", description
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
