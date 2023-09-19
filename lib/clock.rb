require "clockwork"
require_relative "../config/boot"
require_relative "../config/environment"

include Clockwork

# Use locks so multiple clock processes do not schedule dupes
every(10.seconds, "clockwork.very_frequent") do
  if RedisLock.acquire("clockwork:send_stats:v3", 8)
    SendStats.perform_async
  end

  if RedisLock.acquire("clockwork:cache_entry_views", 8)
    CacheEntryViews.perform_async(nil, true)
  end

  if RedisLock.acquire("clockwork:downloader_migration", 8)
    FeedCrawler::PersistCrawlData.perform_async
  end
end

every(1.minutes, "clockwork.frequent") do
  if RedisLock.acquire("clockwork:feed:refresher:scheduler:v2")
    FeedCrawler::ScheduleAll.perform_async
  end

  if RedisLock.acquire("clockwork:harvest:embed:data")
    HarvestEmbeds.perform_async(nil, true)
  end
end

every(1.day, "clockwork.daily", at: "7:00", tz: "UTC") do
  if RedisLock.acquire("clockwork:delete_entries:v2")
    EntryDeleterScheduler.perform_async
  end

  if RedisLock.acquire("clockwork:trial_expiration:v2")
    TrialExpiration.perform_async
  end

  if RedisLock.acquire("clockwork:web_sub_maintenance")
    WebSub::Maintenance.perform_async
  end
end
