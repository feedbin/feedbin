module FeedCrawler
  # Shadows a crawl with a second, identical request that has Feedkit's
  # block_private_addresses enabled, then logs how the two outcomes differ.
  #
  # The flag changes two things, and both need measuring before it can be
  # turned on for real:
  #
  #   1. Hosts whose every address resolves into private space raise
  #      Feedkit::BlockedHost. Some of those are feeds that work today.
  #   2. The blocklist resolves the host itself and connects to the addresses it
  #      validated rather than to the hostname, which changes how the connection
  #      is established for every allowed feed, not just blocked ones.
  #
  # Nothing here may affect the crawl: no crawl_data writes, no parser jobs,
  # no persisted downloads, and every exception is swallowed.
  class BlockedHostShadow
    # Shorter than Feedkit's read: 30 so a slow shadow gives the crawl slot
    # back. Best-effort only -- Timeout raises on the thread, which cannot
    # interrupt a getaddrinfo parked in a GVL-released C call, and production
    # has shown shadows running well past it.
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
      @events      = []
    end

    def call
      return unless sample?

      if no_op_path
        Librato.increment "feed.shadow_block.no_op", source: no_op_path
        Sidekiq.logger.info "BlockedHostShadow verdict=no_op path=#{no_op_path} feed_id=#{@feed_id} url=#{@feed_url}"
        return
      end

      Timeout.timeout(TIMEOUT) { report(probe) }
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
      {outcome: :blocked, exception: exception, ms: elapsed(started)}
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
        block_private_addresses: true,
        blocklist_observer: observer
      )
    rescue Feedkit::ZlibError
      # Mirrors Downloader#download, or the control's retry looks like a
      # regression the flag caused.
      raise if !auto_inflate
      request(auto_inflate: false)
    end

    # Feedkit reports what the blocklist actually did, so nothing here resolves
    # the host a second time. The old second lookup cost another round trip and
    # could answer differently than the one that was judged.
    def observer
      @observer ||= ->(event, data) { @events << [event, data] }
    end

    def resolutions
      @resolutions ||= @events.filter_map { |event, data| data if event == :resolved }
    end

    def dials
      @dials ||= @events.filter_map { |event, data| data if event == :connect }
    end

    def resolution
      @resolution ||= resolutions.last || {}
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
      elsif control[:status] != shadow[:status]
        # A 304 carries an empty body, so its checksum can never match a 200's.
        # Filing that under content_diff reported a freshness disagreement
        # between two servers as a change in the feed.
        "conditional_diff"
      elsif control[:checksum] != shadow[:checksum]
        "content_diff"
      else
        "agree"
      end
    end

    def report(shadow)
      @blocked = shadow[:exception]
      verdict = verdict(shadow)

      Librato.increment "feed.shadow_block", source: verdict
      Librato.increment "feed.shadow_block.rule", source: rule if rule
      Librato.increment "feed.shadow_block.fallback" if fallback?
      Librato.measure "feed.shadow_block.addresses", addresses.count
      Librato.measure "feed.shadow_block.dns_ms", dns_ms if dns_ms

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
        blocked_address:   blocked_addresses.first,
        blocked_host:      @blocked&.host,
        addresses:         addresses.count,
        # http.rb now filters blocked addresses instead of rejecting the host,
        # so a block paired with a usable public address would mean that
        # filtering regressed.
        public_addresses:  public_addresses.count,
        first_family:      first_family,
        dns_ms:            dns_ms,
        hops:              resolutions.count,
        # The address-fallback signal. fallback=true means an address failed and
        # a later one succeeded -- a connection the old single-address behavior
        # would simply have lost.
        dials:             dials.count,
        fallback:          fallback?,
        dials_failed:      dials.count { |dial| dial[:error] },
        redirects:         shadow[:redirects],
        shadow_ms:         shadow[:ms]
      }
      "BlockedHostShadow " + fields.compact.map { |key, value| "#{key}=#{value}" }.join(" ")
    end

    def addresses
      resolution[:addresses] || @blocked&.addresses || []
    end

    def blocked_addresses
      resolution[:blocked] || @blocked&.blocked || []
    end

    def public_addresses
      resolution[:allowed] || (addresses - blocked_addresses)
    end

    # Summed across hops, so a redirect chain reports what the whole request
    # spent resolving rather than only its last hop.
    def dns_ms
      return nil if resolutions.empty?
      (resolutions.sum { |entry| entry[:duration].to_f } * 1000).round
    end

    # True when an address failed and a later one was tried.
    def fallback?
      dials.any? { |dial| dial[:index].to_i > 0 }
    end

    # The family of the address the socket actually used.
    def first_family
      address = dials.last&.fetch(:address, nil) || addresses.first
      return nil if address.nil?
      IPAddr.new(address).ipv6? ? "inet6" : "inet"
    rescue
      nil
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
      blocked_addresses.first && matched_rule(blocked_addresses.first)
    end

    # A block on a redirect hop is the SSRF case the flag exists for; a block
    # at the origin is a feed that simply lives somewhere private.
    def hop
      return nil unless @blocked
      @blocked.host == origin_host ? "origin" : "redirect"
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
