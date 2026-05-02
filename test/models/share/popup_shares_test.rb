require "test_helper"

class Share::PopupSharesTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(
      content: "<p>hello</p>",
      title: "Hello",
      url: "https://example.com/p/1",
      public_id: SecureRandom.hex
    )
  end

  # Each row: share class, URL, expected query keys for share, and the share_link template
  cases = [
    [Share::Twitter, "twitter", "https://twitter.com/intent/tweet", %w[url text]],
    [Share::Facebook, "facebook", "https://www.facebook.com/sharer/sharer.php", %w[u display]],
    [Share::Buffer, "buffer", "http://bufferapp.com/add", %w[url text]],
    [Share::AppDotNet, "app_dot_net", "https://account.app.net/intent/post", %w[url text]]
  ]

  cases.each do |klass, service_id, base_url, query_keys|
    test "#{klass.name}#share builds a popup URL with the entry's fully_qualified_url" do
      result = klass.new.share(entry_id: @entry.id)
      assert_match %r{feedbin\.sharePopup\('#{Regexp.escape(base_url)}\?[^']+'\); return false;}, result[:text]
      query_keys.each do |key|
        assert_match %r{#{key}=}, result[:text]
      end
    end

    test "#{klass.name}#share accepts an entry directly to skip the DB lookup" do
      result = klass.new.share({}, @entry)
      assert_match %r{#{Regexp.escape(base_url)}}, result[:text]
    end

    test "#{klass.name}#share_link returns the popup template URL and behavior" do
      service = @user.supported_sharing_services.create!(service_id: service_id)
      share = klass.new(service)
      link = share.share_link
      assert_match %r{#{Regexp.escape(base_url)}}, link[:url]
      assert_equal "share_popup", link[:html_options]["data-behavior"]
    end
  end
end
