require "test_helper"

module ActivityPub
  class FlattenTest < ActiveSupport::TestCase
    test "should return flattened collection" do
      default_headers = {"Content-Type" => AutoDiscovery::CONTENT_TYPE}

      activities = load_support_json("activity_pub/activities_response.json")

      activities["orderedItems"] = activities["orderedItems"].first(2)

      siracusa_profile = "https://mastodon.social/users/siracusa"
      stub_request_file("activity_pub/profile_response.json", siracusa_profile, headers: default_headers)

      status_url = "https://mastodon.gamedev.place/users/BenHouston3D/statuses/109387836974966237"
      stub_request_file("activity_pub/boost_object.json", status_url, headers: default_headers)

      ben_profile = "https://mastodon.gamedev.place/users/BenHouston3D"
      stub_request_file("activity_pub/benhouston3d_response.json", ben_profile, headers: default_headers)

      result = Sidekiq::Testing.inline! do
        Flatten.flatten(activities)
      end

      assert_equal(load_support_json("activity_pub/profile_response.json"), result.first["actor"])
      assert_equal(load_support_json("activity_pub/profile_response.json"), result.first["object"]["attributedTo"])

      assert_equal(load_support_json("activity_pub/benhouston3d_response.json"), result.last["object"]["attributedTo"])
      assert_equal(load_support_json("activity_pub/boost_object.json")["content"], result.last["object"]["content"])
    end
  end
end