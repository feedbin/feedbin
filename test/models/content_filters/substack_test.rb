require "test_helper"

module ContentFilters
  class SubstackTest < ActiveSupport::TestCase
    test "narrows the document to the newsletter body" do
      document = ContentFormatter.document(%(<div><div class="body markup"><p>hello</p></div><footer>ignore</footer></div>))

      result = ContentFilters::Substack.call(document, {}, {})

      assert_includes result.to_s, "hello"
      assert_not_includes result.to_s, "ignore"
    end

    test "returns the document when the newsletter body is not there" do
      document = ContentFormatter.document("<div><p>hello</p></div>")

      result = ContentFilters::Substack.call(document, {}, {})

      assert_not_nil result, "an HTML::Pipeline filter must never return nil"
      assert_includes result.to_s, "hello"
    end

    test "the whole pipeline survives content without a newsletter body" do
      feed = Feed.create!(feed_url: SecureRandom.hex, feed_type: :newsletter)
      entry = feed.entries.create!(public_id: SecureRandom.hex, newsletter_from: "someone@substack.com", content: "<p>hello</p>", url: "https://example.com/issue")

      formatted = ContentFormatter.format!("<div><p>hello</p></div>", entry)

      assert_includes formatted, "hello"
    end
  end
end
