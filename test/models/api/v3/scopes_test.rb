require "test_helper"

class Api::V3::ScopesTest < ActiveSupport::TestCase
  setup do
    @application = users(:ben).oauth_applications.create!(name: "Feedbin for iOS", redirect_uri: "feedbin-next://oauth/callback")
  end

  test "an application gets read and write unless it was registered with account" do
    assert_equal "read write", Api::V3::Scopes.for(@application)

    @application.update!(scopes: "read write account")
    assert_equal "read write account", Api::V3::Scopes.for(@application)
  end

  test "first_party! gives an application and its live tokens the account scope" do
    live = @application.access_tokens.create!(resource_owner_id: users(:ben).id, scopes: "read write")
    revoked = @application.access_tokens.create!(resource_owner_id: users(:ben).id, scopes: "read write", revoked_at: Time.current)
    other = users(:ann).oauth_applications.create!(name: "Reader", redirect_uri: "")
    theirs = other.access_tokens.create!(resource_owner_id: users(:ben).id, scopes: "read write")

    result = Api::V3::Scopes.first_party!(@application.uid)

    assert_equal "Feedbin for iOS: scopes read write account; 1 tokens upgraded", result
    assert_equal "read write account", @application.reload.scopes.to_s
    assert_equal "read write account", live.reload.scopes.to_s
    assert_equal "read write", revoked.reload.scopes.to_s
    assert_equal ["", "read write"], [other.reload.scopes.to_s, theirs.reload.scopes.to_s]
  end

  test "first_party! with a client id that matches nothing raises" do
    assert_raises(ActiveRecord::RecordNotFound) { Api::V3::Scopes.first_party!("no-such-client") }
  end
end
