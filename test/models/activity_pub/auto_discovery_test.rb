require "test_helper"

module ActivityPub
  class AutoDiscoveryTest < ActiveSupport::TestCase
    test "should return collection" do
      default_headers = {"Content-Type" => AutoDiscovery::CONTENT_TYPE}

      discovery_url = "https://mastodon.social/.well-known/webfinger/?resource=acct:siracusa@mastodon.social"
      stub_request_file("activity_pub/discovery_response.json", discovery_url, headers: default_headers)

      profile_url = "https://mastodon.social/users/siracusa"
      stub_request_file("activity_pub/profile_response.json", profile_url, headers: default_headers)

      outbox_url = "https://mastodon.social/users/siracusa/outbox"
      stub_request_file("activity_pub/outbox_response.json", outbox_url, headers: default_headers)

      activities_url = "https://mastodon.social/users/siracusa/outbox?page=true"
      stub_request_file("activity_pub/activities_response.json", activities_url, headers: default_headers)

      response = AutoDiscovery.find("@siracusa@mastodon.social")

      assert_equal(activities_url, response.url)
      assert_equal(20, response.data.dig("orderedItems").count)
    end
  end
end