require "test_helper"

module ImageCrawler
  class OutsideCamoTest < ActiveSupport::TestCase
    HOSTS = "http://146.190.44.162, http://137.184.35.216,http://64.23.212.49"

    test "is off until both the hosts and the key are set" do
      with_env("CAMO_OUTSIDE_HOSTS" => nil, "CAMO_OUTSIDE_KEY" => nil) do
        assert_not OutsideCamo.enabled?
        assert_empty OutsideCamo.hosts
      end
      with_env("CAMO_OUTSIDE_HOSTS" => HOSTS, "CAMO_OUTSIDE_KEY" => nil) do
        assert_not OutsideCamo.enabled?
      end
      with_env("CAMO_OUTSIDE_HOSTS" => HOSTS, "CAMO_OUTSIDE_KEY" => "outside-key") do
        assert OutsideCamo.enabled?
      end
    end

    test "parses a comma-separated list of origins and picks one" do
      with_env("CAMO_OUTSIDE_HOSTS" => HOSTS, "CAMO_OUTSIDE_KEY" => "outside-key") do
        assert_equal ["http://146.190.44.162", "http://137.184.35.216", "http://64.23.212.49"], OutsideCamo.hosts
        assert_includes OutsideCamo.hosts, OutsideCamo.pick
      end
    end

    # Signed with the fleet's own key, not CAMO_KEY: the outside hosts are
    # throwaway machines and must not hold production's secret.
    test "url signs with the outside key on the given origin" do
      url = "https://yt3.ggpht.com/avatar.jpg"
      with_env("CAMO_OUTSIDE_HOSTS" => HOSTS, "CAMO_OUTSIDE_KEY" => "outside-key") do
        signature = OpenSSL::HMAC.hexdigest("sha1", "outside-key", url)
        hex = url.unpack1("H*")
        assert_equal "http://146.190.44.162/#{signature}/#{hex}", OutsideCamo.url(url, "http://146.190.44.162")
      end
    end
  end
end
