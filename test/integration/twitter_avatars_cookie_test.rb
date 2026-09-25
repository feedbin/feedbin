require "test_helper"

# The CDN caches the avatar redirect as public: a cookie on it would stop
# the cache, or hand one viewer's session to every other viewer. Through
# the whole stack, because the session cookie is the middleware's. Forgery
# protection is off in test, so it is turned on here as in production.
class TwitterAvatarsCookieTest < ActionDispatch::IntegrationTest
  URL = "https://pbs.twimg.com/profile_images/659486593649012736/-TGFT8rs.png"

  test "the redirect sets no cookie" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    with_env("FILES_AUTH_KEY" => "pull-key", "FILES_HOST" => nil) do
      get TwitterAvatar.path(URL), headers: {TwitterAvatarsController::AUTH_HEADER => "pull-key"}

      assert_response :redirect
      assert_nil response.headers["Set-Cookie"]
    end
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
