module WebSub
  class Hub
    def initialize(feed)
      @feed = feed
    end

    def self.subscribe(feed)
      new(feed).subscribe
    end

    def self.unsubscribe(feed)
      new(feed).unsubscribe
    end

    def subscribe
      if @feed.hubs && @feed.self_url
        perform("subscribe")
      end
    end

    def unsubscribe
      if @feed.hubs && @feed.self_url
        perform("unsubscribe")
      end
    end

    private

    def perform(mode)
      @feed.hubs.each do |hub|
        request(hub, mode)
      end
    end

    def request(url, mode)
      # The hub url comes out of the feed document, and this body carries
      # hub.secret and hub.callback, so the socket refuses any host that is not
      # routable on the public internet.
      HTTP.timeout(write: 5, connect: 5, read: 5).follow(max_hops: 2).post(url,
        socket_class: Feedkit::PrivateAddressCheck::Socket,
        form: {
          "hub.mode"     => mode,
          "hub.verify"   => "async",
          "hub.topic"    => @feed.self_url,
          "hub.secret"   => @feed.web_sub_secret,
          "hub.callback" => @feed.web_sub_callback
        })
    rescue Feedkit::PrivateNetworkAddress => exception
      # A hub that resolves privately will never become valid, so this is logged
      # rather than raised: raising would burn the job's whole retry budget.
      Rails.logger.error("WebSub refused hub url=#{url} exception=#{exception.inspect}")
    rescue HTTP::TimeoutError, HTTP::ConnectionError => exception
      Rails.logger.error("WebSub HTTP Error exception=#{exception.inspect}")
    end
  end
end