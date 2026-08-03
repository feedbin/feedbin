module FeedCrawler
  # Shadows a crawl with a second, identical request that has Feedkit's
  # block_ssrf enabled, then logs how the two outcomes differ.
  #
  # block_ssrf swaps in Feedkit::PrivateAddressCheck::Socket, which resolves the
  # host itself, refuses any address that is not routable on the public
  # internet, and races the survivors. That changes three things worth measuring
  # before it is turned on for real:
  #
  #   1. Hosts whose every address is private raise
  #      Feedkit::PrivateNetworkAddress. Some of those are feeds that work today.
  #   2. Resolution moves from the C resolver to Resolv, capped at two addresses
  #      per family and bounded by the socket's own RESOLV_TIMEOUT. A host that
  #      resolves to nothing inside that budget surfaces as a connection error
  #      reading "no address for <host>", not as a timeout.
  #   3. Nothing about FEEDKIT_CURL_HOSTS. Curl is an operator-curated list of
  #      known-safe hosts rather than anything a feed can steer, so it keeps its
  #      shortcut even when blocking. Feedkit applies no address check to those
  #      hosts and there is nothing to compare.
  #
  # Nothing here may affect the crawl: no crawl_data writes, no parser jobs,
  # no persisted downloads, and every exception is swallowed.
  class SsrfShadow
    # Shorter than Feedkit's read: 30 so a slow shadow gives the crawl slot
    # back. Best-effort only -- Timeout raises on the thread, which cannot
    # interrupt a resolver parked in a GVL-released call, and production has
    # shown shadows running well past it.
    TIMEOUT = 20

    # One duplicate request per feed per day. Random sampling picks the feeds,
    # this stops the same feed being re-sampled once it has answered.
    SEEN_TTL = 24 * 60 * 60

    # How a resolution that produced nothing arrives, now that Resolv swallows
    # its own errors and the socket raises on the empty candidate list.
    NO_ADDRESS = "no address for".freeze

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
      @shadow      = {}
    end

    def call
      return unless sample?

      if no_op_path
        Librato.increment "feed.shadow_ssrf.no_op", source: no_op_path
        Sidekiq.logger.info "SsrfShadow verdict=no_op path=#{no_op_path} feed_id=#{@feed_id} url=#{@feed_url}"
        return
      end

      Timeout.timeout(TIMEOUT) { report(probe) }
    rescue => exception
      Sidekiq.logger.info "SsrfShadow failed feed_id=#{@feed_id} exception=#{exception.class} message=#{exception.message.inspect}"
    end

    # Percentage of crawls to shadow. Absent or 0 leaves the whole thing inert.
    def percentage
      ENV["SHADOW_BLOCK_SSRF"].to_i
    end

    def sample?
      return false unless percentage > 0
      return false unless rand(100) < percentage
      Sidekiq.redis { it.set(seen_key, 1, nx: true, ex: SEEN_TTL) }
    end

    def seen_key
      "shadow_ssrf:#{@feed_id}"
    end

    # The one path where blocking changes nothing, so a duplicate request would
    # only compare a host against itself: curl keeps its shortcut because that
    # list is operator-curated and known safe, and it resolves and connects on
    # its own, so Feedkit never gets to check its addresses.
    #
    # Still a named path rather than a boolean: the metric is sourced on it, and
    # proxied hosts were the other one until Feedkit dropped proxy support.
    def no_op_path
      return @no_op_path if defined?(@no_op_path)
      @no_op_path = ("curl" if env_hosts("FEEDKIT_CURL_HOSTS").include?(origin_host))
    end

    def env_hosts(name)
      ENV[name]&.split(",")&.map(&:strip) || []
    end

    def probe
      started = clock
      response = request
      {outcome: :ok, status: response.status.code, checksum: response.checksum, redirects: response.redirects.count, ms: elapsed(started)}
    rescue Feedkit::PrivateNetworkAddress => exception
      {outcome: :blocked, message: exception.message, ms: elapsed(started)}
    rescue Feedkit::Error => exception
      {outcome: :error, error: exception.class.name, message: exception.message,
       status: error_status(exception), ms: elapsed(started)}
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
        block_ssrf:    true
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
      elsif shadow[:outcome] != :ok
        # Both failed. Now that an error carries its status, comparing statuses
        # here would read two failures as a freshness disagreement.
        "agree"
      elsif control[:status] != shadow[:status]
        # A 304 carries an empty body, so its checksum can never match a 200's.
        # Filing that under content_diff reports a freshness disagreement
        # between two servers as a change in the feed.
        "conditional_diff"
      elsif control[:checksum] != shadow[:checksum]
        "content_diff"
      else
        "agree"
      end
    end

    def report(shadow)
      @shadow = shadow
      verdict = verdict(shadow)

      Librato.increment "feed.shadow_ssrf", source: verdict
      Librato.increment "feed.shadow_ssrf.rule", source: rule if rule
      Librato.increment "feed.shadow_ssrf.status", source: shadow[:status] if failed_status?(shadow)
      Librato.increment "feed.shadow_ssrf.dns_failed" if dns_failed?
      Librato.measure "feed.shadow_ssrf.addresses", addresses.count
      Librato.measure "feed.shadow_ssrf.dns_ms", resolution[:ms] if resolution[:ms]

      Sidekiq.logger.info log_line(verdict, shadow)
    end

    def log_line(verdict, shadow)
      fields = {
        verdict:          verdict,
        feed_id:          @feed_id,
        url:              @feed_url.inspect,
        control:          control[:outcome],
        control_status:   control[:status],
        control_error:    control[:error],
        shadow:           shadow[:outcome],
        shadow_status:    shadow[:status],
        shadow_error:     shadow[:error],
        hop:              hop,
        rule:             rule,
        blocked_address:  blocked_address,
        blocked_host:     blocked_host,
        addresses:        addresses.count,
        # Feedkit rejects an address rather than the host, so a block reported
        # alongside a usable public address would mean that filtering broke.
        public_addresses: public_addresses.count,
        # Resolv is asked for both families and keeps at most two of each, then
        # races them, so neither ordering nor a single "first" address decides
        # which one gets used.
        v6:               families[:v6],
        v4:               families[:v4],
        dns_ms:           resolution[:ms],
        # A resolution that produced nothing inside the socket's RESOLV_TIMEOUT.
        # This was the dominant failure two runs ago, so it is counted rather
        # than buried inside a generic connection error.
        dns_failed:       dns_failed?,
        redirects:        shadow[:redirects],
        shadow_ms:        shadow[:ms]
      }
      "SsrfShadow " + fields.compact.map { |key, value| "#{key}=#{value}" }.join(" ")
    end

    def dns_failed?
      @shadow[:outcome] == :error && @shadow[:message].to_s.include?(NO_ADDRESS)
    end

    # A rejection and a rate limit both arrive as Feedkit::ClientError but call
    # for different responses, so the status is pulled off the response the
    # error carries rather than left inside the class name.
    def error_status(exception)
      exception.response.status.code if exception.respond_to?(:response) && exception.response
    end

    def failed_status?(shadow)
      shadow[:outcome] == :error && shadow[:status]
    end

    # Resolved with Feedkit's own resolver so the candidate list and the
    # classification match what the request actually judged. It is a second
    # resolution taken just after the request, so treat it as indicative -- the
    # answer can differ from the one the socket saw.
    def resolution
      @resolution ||= begin
        started = clock
        found = Feedkit::PrivateAddressCheck::Socket.addresses(resolved_host, resolve_timeout)
        {addresses: found, ms: elapsed(started)}
      rescue => exception
        {addresses: [], error: exception.class.name}
      end
    end

    def resolve_timeout
      Feedkit::PrivateAddressCheck::Socket::RESOLV_TIMEOUT
    end

    def addresses
      resolution[:addresses]
    end

    def families
      @families ||= addresses.each_with_object({v6: 0, v4: 0}) do |address, counts|
        ip = ip_for(address)
        counts[ip.ipv6? ? :v6 : :v4] += 1 if ip
      end
    end

    def public_addresses
      @public_addresses ||= addresses.reject { |address| private?(address) }
    end

    def private?(address)
      ip = ip_for(address)
      ip ? Feedkit::PrivateAddressCheck.private_address?(ip) : false
    end

    # Feedkit's resolver returns IPAddr, and IPAddr.new raises on one of those
    # rather than passing it through. Parsing unconditionally sent every
    # resolved address down the rescue, so each one read as nil: nothing was
    # private, every address was counted as publicly routable, and both family
    # counts stayed zero. Only blocked_address arrives as a String.
    def ip_for(address)
      return address if address.is_a?(IPAddr)
      IPAddr.new(address)
    rescue
      nil
    end

    # "example.com resolves to a private address: 10.0.0.1"
    def blocked_message
      return @blocked_message if defined?(@blocked_message)
      @blocked_message = @shadow[:message]&.match(/\A(?<host>\S+) resolves to a private address: (?<address>\S+)\z/)
    end

    def blocked_host
      blocked_message && blocked_message[:host]
    end

    def blocked_address
      blocked_message && blocked_message[:address]
    end

    # Mirrors PrivateAddressCheck.private_address?'s order so the attribution
    # matches the check that actually ran.
    def matched_rule(address)
      ip = ip_for(address) or return nil
      ip = ip.native if ip.ipv6? && (ip.ipv4_mapped? || ip.ipv4_compat?)
      return "private" if ip.private?
      return "loopback" if ip.loopback?
      return "link_local" if ip.link_local?
      cidr = Feedkit::PrivateAddressCheck::CIDR_LIST.find { |entry| entry.include?(ip) }
      cidr && "#{cidr}/#{cidr.prefix}"
    end

    def rule
      blocked_address && matched_rule(blocked_address)
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
