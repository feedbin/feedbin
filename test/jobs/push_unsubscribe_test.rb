require "test_helper"

class PushUnsubscribeTest < ActiveSupport::TestCase
  test "should unsubscribe" do
    hub_url = "http://hub.example.com/"
    feed = Feed.first
    feed.update(hubs: [hub_url])

    secret = Push.hub_secret(feed.id)
    uri = URI(ENV["PUSH_URL"])

    result = stub_request(:post, hub_url).with(body: {
      "hub.callback" => Rails.application.routes.url_helpers.push_feed_url(feed, protocol: uri.scheme, host: uri.host),
      "hub.mode"     => "unsubscribe",
      "hub.secret"   => secret,
      "hub.topic"    => feed.self_url,
      "hub.verify"   => "async"
    }).to_return(status: 202)

    PushUnsubscribe.new.perform(feed.id, feed.self_url)

    assert_requested :post, hub_url
  end
end
