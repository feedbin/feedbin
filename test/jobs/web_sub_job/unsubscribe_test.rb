require "test_helper"

module WebSubJob
  class UnsubscribeTest < ActiveSupport::TestCase
    test "should unsubscribe" do
      hub_url = "http://hub.example.com/"
      feed = Feed.first
      feed.update(hubs: [hub_url])

      result = stub_request(:post, hub_url).with(body: {
        "hub.callback" => feed.web_sub_callback,
        "hub.mode"     => "unsubscribe",
        "hub.secret"   => feed.web_sub_secret,
        "hub.topic"    => feed.self_url,
        "hub.verify"   => "async"
      }).to_return(status: 202)

      Unsubscribe.new.perform(feed.id)

      assert_requested :post, hub_url
    end
  end
end