require "test_helper"

class ChapterParserTest < ActiveSupport::TestCase
  test "refuses an enclosure URL at a private address" do
    parser = ChapterParser.new
    parser.instance_variable_set(:@url, "http://127.0.0.1:9/audio.mp3")

    assert_raises Feedkit::PrivateNetworkAddress do
      parser.request
    end
  end

  test "passes enclosure credentials as keyword arguments" do
    url = "https://example.com/audio.mp3"
    request = stub_request(:get, url)
      .with(basic_auth: ["listener", "secret"])
      .to_return(body: "audio")
    parser = ChapterParser.new
    parser.instance_variable_set(:@url, "https://listener:secret@example.com/audio.mp3")

    parser.request

    assert_requested request
  end

  test "a redirect loop from an enclosure does not fail the job" do
    entry = create_entry(Feed.first)
    entry.update!(data: entry.data.merge("enclosure_url" => "https://example.com/audio.mp3"))
    parser = ChapterParser.new

    parser.stub(:request, -> { raise HTTP::Redirector::EndlessRedirectError }) do
      assert_nothing_raised { parser.perform(entry.id) }
    end
  end

  test "a TLS failure from an enclosure does not fail the job" do
    entry = create_entry(Feed.first)
    entry.update!(data: entry.data.merge("enclosure_url" => "https://example.com/audio.mp3"))
    parser = ChapterParser.new

    parser.stub(:request, -> { raise OpenSSL::SSL::SSLError }) do
      assert_nothing_raised { parser.perform(entry.id) }
    end
  end
end
