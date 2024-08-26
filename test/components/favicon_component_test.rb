require "test_helper"

class FaviconComponentTest < ComponentTestCase

  setup do
    @feed = feeds(:daring_fireball)
  end

  test "generated favicon" do
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap"><span class="favicon-default favicon-mask" data-color-hash-seed="daringfireball.net"><span class="favicon-inner"></span></span></span>), output.to_s
  end

  test "cdn favicon" do
    favicon = Favicon.create!(url: "http://example.com/favicon.ico", host: @feed.host)
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap"><span class="favicon host-daringfireball-net" style="background-image: url(https://favicons.example.com/favicon.ico);"></span></span>), output.to_s
  end

  test "newsletter favicon" do
    @feed.newsletter!
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap collection-favicon"><svg width="16.0" height="12.0" class="favicon-newsletter"><use href="#favicon-newsletter"></use></svg></span>), output.to_s
  end

  test "pages default favicon" do
    @feed.pages!
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap collection-favicon"><svg width="14.0" height="16.0" class="favicon-saved"><use href="#favicon-saved"></use></svg></span>), output.to_s
  end

  test "pages article favicon" do
    @feed.pages!
    entry = create_entry(@feed)
    entry.update(url: "http://example.com/article")
    favicon = Favicon.create!(url: "http://example.com/favicon.ico", host: entry.hostname)

    output = render FaviconComponent.new(feed: @feed, entry: entry)
    assert_equal %(<span class="favicon-wrap"><span class="favicon host-example-com" style="background-image: url(https://favicons.example.com/favicon.ico);"></span></span>), output.to_s
  end

  test "twitter user favicon" do
    tweet = load_tweet("one")
    @feed.update(options: {twitter_user: tweet["user"]})
    output = render FaviconComponent.new(feed: @feed)
    favicon_markup = %(<span class="favicon-wrap twitter-profile-image"><img alt="" onerror="this.onerror=null;this.src='http://test.host/assets/favicon-profile-default-65075e4958d19345a99f697e3b7eb70a82851108a33d28f85f70c0a3df02b4c5.png';" src="/files/icons/38cdd03c8be8fcc27c7e933b093f0b4a7015c218/68747470733a2f2f7062732e7477696d672e636f6d2f70726f66696c655f696d616765732f3934363434383034353431353235363036342f626d4579337238412e6a7067"></span>)
    assert_equal favicon_markup, output.to_s
  end

  test "feed icon" do
    @feed.custom_icon = "http://example.com/custom.png"
    output = render FaviconComponent.new(feed: @feed)
    assert_equal %(<span class="favicon-wrap twitter-profile-image icon-format-round"><img alt="" onerror="this.onerror=null;this.src='http://test.host/assets/favicon-profile-default-65075e4958d19345a99f697e3b7eb70a82851108a33d28f85f70c0a3df02b4c5.png';" src="/files/icons/91a28cf86b9cdea1dcc6c7570f922135db424123/687474703a2f2f6578616d706c652e636f6d2f637573746f6d2e706e67"></span>), output.to_s
  end
end


