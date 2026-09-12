module ImageCrawler
  # A go-camo fleet outside Feedbin's static addresses, for sources that
  # rate-limit per address (YouTube avatars). The hosts hold no state and
  # reach nothing of ours; Feedbin makes one outbound request per fetch,
  # signed with a key that only this fleet shares. CAMO_OUTSIDE_HOSTS is a
  # comma-separated list of origins, scheme included; CAMO_OUTSIDE_KEY is
  # that fleet's key. Unset means direct fetches.
  module OutsideCamo
    def self.hosts
      ENV["CAMO_OUTSIDE_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def self.key
      ENV["CAMO_OUTSIDE_KEY"].presence
    end

    def self.enabled?
      hosts.any? && key.present?
    end

    # One host per image, chosen at schedule time, so the run spreads over
    # every address without DNS tricks.
    def self.pick
      hosts.sample
    end

    def self.url(url, host)
      RemoteFile.camo_url(url, host: host, key: key)
    end
  end
end
