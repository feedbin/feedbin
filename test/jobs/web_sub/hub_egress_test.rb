require "test_helper"

module WebSub
  class HubEgressTest < ActiveSupport::TestCase
    # A hub url arrives in feed content, and the POST body carries hub.secret
    # and hub.callback. Asserting on the exception is not enough here — what
    # matters is that nothing reaches the socket, so the test listens.
    test "does not connect to a hub at a private address" do
      server = TCPServer.new("127.0.0.1", 0)
      hub_url = "http://127.0.0.1:#{server.addr[1]}/"

      feed = Feed.first
      feed.update(hubs: [hub_url])

      Subscribe.new.perform(feed.id)

      assert_raises IO::WaitReadable, "the hub POST reached the socket" do
        server.accept_nonblock
      end
    ensure
      server&.close
    end

    test "a refused private hub does not fail the job" do
      feed = Feed.first
      feed.update(hubs: ["http://127.0.0.1:9/"])

      assert_nothing_raised do
        Subscribe.new.perform(feed.id)
      end
    end
  end
end
