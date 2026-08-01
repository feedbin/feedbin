module FeedCrawler
  # Shadows a crawl with a second, identical request that has Feedkit's
  # block_private_addresses enabled, then logs how the two outcomes differ.
  #
  # The flag changes two things, and both need measuring before it can be
  # turned on for real:
  #
  #   1. Hosts resolving to private space raise Feedkit::BlockedHost. Some of
  #      those are feeds that work today.
  #   2. HTTP::Blocklist#validate! resolves the host itself and connects to
  #      addresses.first instead of the hostname, so the connection loses
  #      TCPSocket's address-by-address fallback and DNS moves outside the
  #      connect timeout. That affects every allowed feed, not just blocked
  #      ones.
  #
  # Nothing here may affect the crawl: no crawl_data writes, no parser jobs,
  # no persisted downloads, and every exception is swallowed.
  class BlockedHostShadow
    # Shorter than Feedkit's read: 30 so a slow shadow gives the crawl slot
    # back. Best-effort only -- Timeout raises on the thread, which cannot
    # interrupt a getaddrinfo parked in a GVL-released C call.
    TIMEOUT = 20

    # One duplicate request per feed per day. Random sampling picks the feeds,
    # this stops the same feed being re-sampled once it has answered.
    SEEN_TTL = 24 * 60 * 60

    def self.call(...)
      new(...).call
    end

    def initialize(feed_id:, feed_url:, subscribers:, crawl_data:, response: nil, error: nil)
      @feed_id     = feed_id
      @feed_url    = feed_url
      @subscribers = subscribers
      # The pristine argument hash, not the Downloader's CrawlData, which has
      # already been overwritten with this crawl's etag and last_modified.
      # Replaying those would 304 where the control got a 200.
      @crawl_data  = CrawlData.new(crawl_data || {})
      @response    = response
      @error       = error
    end

    def call
      return unless sample?

      if no_op_path
        Librato.increment "feed.shadow_block.no_op", source: no_op_path
        Sidekiq.logger.info "BlockedHostShadow verdict=no_op path=#{no_op_path} feed_id=#{@feed_id} url=#{@feed_url}"
        return
      end

      report(probe)
    rescue => exception
      Sidekiq.logger.info "BlockedHostShadow failed feed_id=#{@feed_id} exception=#{exception.class} message=#{exception.message.inspect}"
    end

    # Percentage of crawls to shadow. Absent or 0 leaves the whole thing inert.
    def percentage
      ENV["SHADOW_BLOCK_PRIVATE_ADDRESSES"].to_i
    end

    def sample?
      return false unless percentage > 0
      return false unless rand(100) < percentage
      Sidekiq.redis { it.set(seen_key, 1, nx: true, ex: SEEN_TTL) }
    end

    def seen_key
      "shadow_block:#{@feed_id}"
    end

    # Paths where block_private_addresses is silently ignored: Curl.download
    # returns before the client is built, and a proxied request only warns
    # because the proxy does the resolving.
    def no_op_path
      return @no_op_path if defined?(@no_op_path)
      @no_op_path = begin
        if env_hosts("FEEDKIT_CURL_HOSTS").include?(origin_host)
          "curl"
        elsif env_hosts("FEEDKIT_PROXIED_HOSTS").include?(origin_host)
          "proxy"
        end
      end
    end

    def env_hosts(name)
      ENV[name]&.split(",")&.map(&:strip) || []
    end

    def probe
      started = clock
      response = request
      {outcome: :ok, status: response.status.code, checksum: response.checksum, redirects: response.redirects.count, ms: elapsed(started)}
    rescue Feedkit::BlockedHost => exception
      {outcome: :blocked, message: exception.message, ms: elapsed(started)}
    rescue Feedkit::Error => exception
      {outcome: :error, error: exception.class.name, ms: elapsed(started)}
    ensure
      # Never persist!, so the tempfile would otherwise sit until GC.
      begin
        File.unlink(response.path) if response
      rescue SystemCallError
      end
    end

    def request(auto_inflate: true)
      parsed_url = Feedkit::BasicAuth.parse(@feed_url)
      url = @crawl_data.redirected_to || parsed_url.url

      Feedkit::Request.download(url,
        username:      parsed_url.username,
        password:      parsed_url.password,
        last_modified: @crawl_data.last_modified,
        etag:          @crawl_data.etag,
        auto_inflate:  auto_inflate,
        # Deliberately identical to the control's. A distinct agent would let
        # servers that vary on it explain away any difference we measure.
        user_agent:    "Feedbin feed-id:#{@feed_id} - #{@subscribers} subscribers",
        block_private_addresses: true
      )
    rescue Feedkit::ZlibError
      # Mirrors Downloader#download, or the control's retry looks like a
      # regression the flag caused.
      raise if !auto_inflate
      request(auto_inflate: false)
    end

    def control
      @control ||= if @response
        {outcome: :ok, status: @response.status.code, checksum: @response.checksum}
      else
        {outcome: :error, error: @error&.class&.name}
      end
    end

    def verdict(shadow)
      if shadow[:outcome] == :blocked
        control[:outcome] == :error ? "blocked_control_error" : "blocked_control_ok"
      elsif shadow[:outcome] == :error && control[:outcome] == :ok
        "regressed"
      elsif shadow[:outcome] == :ok && control[:outcome] == :error
        "recovered"
      elsif control[:checksum] != shadow[:checksum]
        "content_diff"
      else
        "agree"
      end
    end

    def report(shadow)
      @shadow_message = shadow[:message]
      verdict = verdict(shadow)

      Librato.increment "feed.shadow_block", source: verdict
      Librato.increment "feed.shadow_block.rule", source: rule if rule
      Librato.measure "feed.shadow_block.addresses", addresses.count
      Librato.measure "feed.shadow_block.dns_ms", resolution[:ms] if resolution[:ms]

      Sidekiq.logger.info log_line(verdict, shadow)
    end

    def log_line(verdict, shadow)
      fields = {
        verdict:           verdict,
        feed_id:           @feed_id,
        url:               @feed_url.inspect,
        control:           control[:outcome],
        control_status:    control[:status],
        control_error:     control[:error],
        shadow:            shadow[:outcome],
        shadow_status:     shadow[:status],
        shadow_error:      shadow[:error],
        hop:               hop,
        rule:              rule,
        blocked_address:   blocked_address,
        blocked_host:      blocked_host,
        addresses:         addresses.count,
        # A block landing here while a usable public address exists is a false
        # positive validate! creates on its own: any blocked address rejects
        # the whole host, even when TCPSocket would have reached the good one.
        public_addresses:  public_addresses.count,
        first_family:      first_family,
        dns_ms:            resolution[:ms],
        dns_error:         resolution[:error],
        redirects:         shadow[:redirects],
        shadow_ms:         shadow[:ms]
      }
      "BlockedHostShadow " + fields.compact.map { |key, value| "#{key}=#{value}" }.join(" ")
    end

    # HTTP::Blocklist reports only the first offending address, so resolve the
    # host again to see the whole answer it judged.
    def resolution
      @resolution ||= begin
        started = clock
        found = Addrinfo.getaddrinfo(resolved_host, nil, nil, :STREAM).map(&:ip_address).uniq
        {addresses: found, ms: elapsed(started)}
      rescue => exception
        {addresses: [], error: exception.class.name}
      end
    end

    def addresses
      resolution[:addresses]
    end

    def public_addresses
      addresses.reject { |address| matched_rule(address) }
    end

    # Which address family addresses.first belongs to -- the address the
    # blocklist hands to the socket, with no fallback if it is unreachable.
    def first_family
      return nil if addresses.empty?
      IPAddr.new(addresses.first).ipv6? ? "inet6" : "inet"
    end

    # Mirrors PrivateAddress.match?'s order so the attribution matches the
    # check that actually ran.
    def matched_rule(address)
      ip = IPAddr.new(address).native
      return "private" if ip.private?
      return "loopback" if ip.loopback?
      return "link_local" if ip.link_local?
      cidr = Feedkit::PrivateAddress::CIDRS.find { |entry| entry.include?(ip) }
      cidr && "#{cidr}/#{cidr.prefix}"
    rescue
      nil
    end

    def rule
      blocked_address && matched_rule(blocked_address)
    end

    # "example.com resolves to blocked address: 10.0.0.1", or for a hostname
    # rule, "blocked host: example.com". Feedkit configures no hostname rules,
    # so in practice only the first form appears.
    def blocked_message
      return @blocked_message if defined?(@blocked_message)
      @blocked_message = @shadow_message&.match(/\A(?<host>\S+) resolves to blocked address: (?<address>\S+)\z/)
    end

    def blocked_host
      blocked_message && blocked_message[:host]
    end

    def blocked_address
      blocked_message && blocked_message[:address]
    end

    # A block on a redirect hop is the SSRF case the flag exists for; a block
    # at the origin is a feed that simply lives somewhere private.
    def hop
      return nil unless blocked_host
      blocked_host == origin_host ? "origin" : "redirect"
    end

    def resolved_host
      blocked_host || origin_host
    end

    def origin_host
      @origin_host ||= begin
        url = @crawl_data.redirected_to || Feedkit::BasicAuth.parse(@feed_url).url
        Addressable::URI.heuristic_parse(url).host
      rescue
        nil
      end
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed(started)
      return nil unless started
      ((clock - started) * 1000).round
    end
  end
end
