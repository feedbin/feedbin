require "test_helper"

class WebSubSubscribeTest < ActiveSupport::TestCase
  test "should subscribe" do
    hub_url = "http://hub.example.com/"
    feed = Feed.first
    feed.update(hubs: [hub_url])

    result = stub_request(:post, hub_url).with(body: {
      "hub.callback" => feed.web_sub_callback,
      "hub.mode"     => "subscribe",
      "hub.secret"   => feed.web_sub_secret,
      "hub.topic"    => feed.self_url,
      "hub.verify"   => "async"
    }).to_return(status: 202)

    WebSubSubscribe.new.perform(feed.id)

    assert_requested :post, hub_url
  end

  test "should not subscribe no self_url" do
    hub_url = "http://hub.example.com/"
    feed = Feed.first
    feed.update(hubs: [hub_url], self_url: nil)

    result = stub_request(:post, hub_url)

    WebSubSubscribe.new.perform(feed.id)

    assert_not_requested :post, hub_url
  end
end
