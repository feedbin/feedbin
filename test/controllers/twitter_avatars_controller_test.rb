require "test_helper"

class TwitterAvatarsControllerTest < ActionController::TestCase
  URL = "https://pbs.twimg.com/profile_images/659486593649012736/-TGFT8rs.png"
  KEY = "pull-key"

  setup do
    flush_redis
  end

  test "a wrong pull key is not found" do
    with_env("FILES_AUTH_KEY" => KEY, "FILES_HOST" => nil) do
      @request.headers[TwitterAvatarsController::AUTH_HEADER] = "wrong"
      get :show, params: signed_params(URL)
      assert_response :not_found
    end
  end

  test "a missing pull key is not found" do
    with_env("FILES_AUTH_KEY" => KEY, "FILES_HOST" => nil) do
      get :show, params: signed_params(URL)
      assert_response :not_found
    end
  end

  test "a bad signature is not found" do
    authorized do
      get :show, params: {signature: "asdf", url: URL.unpack1("H*")}
      assert_response :not_found
    end
  end

  test "a url that is not hex is not found" do
    authorized do
      get :show, params: {signature: TwitterAvatar.sign(URL), url: "zz1"}
      assert_response :not_found
    end
  end

  test "a url without a scheme is not found" do
    authorized do
      get :show, params: signed_params("pbs.twimg.com/profile_images/1/a.png")
      assert_response :not_found
    end
  end

  test "a hit redirects to the stored copy and is cached forever" do
    authorized do
      with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
        row = create_image_row(provider: :twitter_avatar, provider_id: TwitterAvatar.fingerprint(URL), feed_id: nil, kind: :avatar, url: URL, variant: "400x400")

        get :show, params: signed_params(URL)

        assert_redirected_to "https://images.example.com/#{row.storage_path}"
        assert_includes response.headers["Cache-Control"], "public"
        assert_includes response.headers["Cache-Control"], "max-age=#{100.years.to_i}"
      end
    end
  end

  # Cached for a day, not forever: a copy run that lands later must reach
  # the CDN.
  test "a miss redirects to camo for a day" do
    authorized do
      get :show, params: signed_params(URL)

      assert_redirected_to Camo.url(URL)
      assert_includes response.headers["Cache-Control"], "public"
      assert_includes response.headers["Cache-Control"], "max-age=86400"
    end
  end

  private

  def signed_params(url)
    {signature: TwitterAvatar.sign(url), url: url.unpack1("H*")}
  end

  def authorized
    with_env("FILES_AUTH_KEY" => KEY, "FILES_HOST" => nil) do
      @request.headers[TwitterAvatarsController::AUTH_HEADER] = KEY
      yield
    end
  end
end
