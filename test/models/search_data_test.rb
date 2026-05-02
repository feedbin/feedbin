require "test_helper"

class SearchDataTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(
      content: %(<p>Hello</p><p><a href="https://example.com/path">link</a> and <a href="https://www.evil.test">other</a></p>),
      title: "  Hello World  ",
      url: "https://example.com/path/article",
      public_id: SecureRandom.hex
    )
  end

  test "to_h returns the canonical search document for an entry" do
    hash = SearchData.new(@entry).to_h
    assert_equal @entry.id, hash[:id]
    assert_equal @entry.feed_id, hash[:feed_id]
    assert_equal "Hello World", hash[:title]
    assert_kind_of Array, hash[:url]
    assert_includes hash[:url], "https://example.com/path/article"
    assert_kind_of Integer, hash[:word_count]
    assert_operator hash[:word_count], :>, 0
    assert_equal "feed", hash[:type]
  end

  test "title returns nil when the entry has no title text" do
    @entry.update!(title: nil)
    assert_nil SearchData.new(@entry).title
  end

  test "text returns nil when document content is empty" do
    @entry.update!(content: "<div></div>")
    assert_nil SearchData.new(@entry).text
  end

  test "url splits the fully_qualified_url into searchable tokens" do
    parts = SearchData.new(@entry).url
    assert_includes parts, "https://example.com/path/article"
    assert_includes parts, "example.com"
    assert_includes parts, "path"
    assert_includes parts, "article"
  end

  test "url returns just the entry url when it doesn't respond to split" do
    @entry.stub :fully_qualified_url, nil do
      assert_equal [nil], SearchData.new(@entry).url
    end
  end

  test "links returns the registered domain and host of every <a href>" do
    links = SearchData.new(@entry).links
    assert_includes links, "example.com"
    assert_includes links, "evil.test"
  end

  test "type is youtube for youtube entries" do
    @entry.stub :youtube?, true do
      assert_equal "youtube", SearchData.new(@entry).type
    end
  end

  test "type is podcast for podcast entries" do
    @entry.stub :podcast?, true do
      assert_equal "podcast", SearchData.new(@entry).type
    end
  end

  test "type is newsletter for newsletter entries" do
    @entry.stub :newsletter?, true do
      assert_equal "newsletter", SearchData.new(@entry).type
    end
  end

  test "to_h adds twitter_* fields when entry is a tweet" do
    user = OpenStruct.new(screen_name: "alice", name: "Alice A")
    main_tweet = OpenStruct.new(user: user, quoted_status?: false, urls?: true)
    main_tweet.define_singleton_method(:media?) { false }
    fake_tweet = OpenStruct.new(
      main_tweet: main_tweet,
      retweeted_status?: false,
      quoted_status?: false,
      twitter_media?: false
    )
    @entry.stub :tweet?, true do
      @entry.stub :tweet, fake_tweet do
        hash = SearchData.new(@entry).to_h
        assert_equal "twitter", hash[:type]
        assert_equal "alice @alice", hash[:twitter_screen_name]
        assert_equal "Alice A", hash[:twitter_name]
        refute hash[:twitter_retweet]
        refute hash[:twitter_quoted]
        refute hash[:twitter_media]
        refute hash[:twitter_image]
        assert hash[:twitter_link]
      end
    end
  end

  test "tweets pushes the quoted_status when present" do
    quoted = Object.new
    main_tweet = OpenStruct.new(quoted_status?: true, quoted_status: quoted)
    main_tweet.define_singleton_method(:media?) { false }
    main_tweet.define_singleton_method(:urls?) { false }
    fake_tweet = OpenStruct.new(main_tweet: main_tweet)
    @entry.stub :tweet, fake_tweet do
      tweets = SearchData.new(@entry).tweets
      assert_equal 2, tweets.size
      assert_same quoted, tweets.last
    end
  end

  test "document falls back to an empty fragment when the pipeline raises InvalidDocumentException" do
    HTML::Pipeline.stub :new, ->(*) { raise HTML::Pipeline::Filter::InvalidDocumentException.new("bad") } do
      doc = SearchData.new(@entry).document
      assert_equal "", doc.to_s.strip
    end
  end
end
