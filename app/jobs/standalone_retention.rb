# `standalone_request_at` is stamped by the podcast API and nothing clears
# it. This module holds only the TTL; the rule itself -- whether a feed is
# pruned at all, and how deep -- lives in EntryDeleter#prunable? and
# #entry_limit, and in FeedCrawler::Schedule#refresh_feeds, which bounds the
# crawl set by the same TTL. See
# docs/superpowers/specs/2026-08-24-standalone-feed-retention-design.md.
module StandaloneRetention
  # Api::Podcasts::V1::FeedsController#show touches the column on every
  # lookup, so it records the most recent request, not the first.
  TTL = 90.days
end
