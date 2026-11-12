require "test_helper"

class MercuryParserTest < ActiveSupport::TestCase
  CONFIGURED = {
    "EXTRACT_HOST" => "https://extract.example.com",
    "EXTRACT_USER" => "feedbin",
    "EXTRACT_SECRET" => "secret"
  }.freeze
  URL = "https://example.com/articles/1?page=2"

  test "service_url signs the url for the extract service" do
    with_env(CONFIGURED) do
      signature = OpenSSL::HMAC.hexdigest("sha1", "secret", URL)
      assert_equal "https://extract.example.com/parser/feedbin/#{signature}?base64_url=#{Base64.urlsafe_encode64(URL)}",
        MercuryParser.new(URL).service_url
    end
  end

  test "service_url is nil, and raises nothing, when any part of the extract service is not configured" do
    CONFIGURED.each_key do |missing|
      with_env(CONFIGURED.merge(missing => nil)) do
        raised = []
        service_url = :unset
        TracePoint.new(:raise) { raised << _1.raised_exception.class }.enable do
          service_url = MercuryParser.new(URL).service_url
        end

        assert_nil service_url, "without #{missing}"
        assert_empty raised, "without #{missing}"
      end
    end
  end

  test "service_url is nil when a part of the extract service is blank" do
    with_env(CONFIGURED.merge("EXTRACT_HOST" => "")) do
      assert_nil MercuryParser.new(URL).service_url
    end
  end

  test "fetching without the extract service configured says so" do
    with_env(CONFIGURED.transform_values { nil }) do
      error = assert_raises(MercuryParser::NotConfigured) { MercuryParser.parse(URL) }
      assert_includes error.message, "EXTRACT_HOST"
    end
  end

  test "a parser built from saved data reads it without the extract service" do
    with_env(CONFIGURED.transform_values { nil }) do
      parser = MercuryParser.new(nil, data: {"result" => {"title" => "Saved", "content" => "<p>Body</p>"}, "url" => URL})

      assert_equal "Saved", parser.title
      assert_equal "<p>Body</p>", parser.content
    end
  end
end
