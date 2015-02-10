require 'clockwork'
require_relative '../config/boot'
require_relative '../config/environment'

include Clockwork

# Use locks so multiple clock processes do not schedule dupes
every(1.minutes, 'clockwork.frequent') do

  if RedisLock.acquire("clockwork:feed:refresher:scheduler")
    FeedRefresherScheduler.perform_async
  end

  if RedisLock.acquire("clockwork:send_stats")
    SendStats.perform_async
  end

end

every(1.day, 'clockwork.daily', at: '12:00', tz: 'UTC') do

  if RedisLock.acquire("clockwork:delete_unread_entries")
    UnreadEntryDeleterScheduler.perform_async
  end

  if RedisLock.acquire("clockwork:delete_entries")
    EntryDeleterScheduler.perform_async
  end

  if RedisLock.acquire("clockwork:trial_expiration")
    TrialExpiration.perform_async
  end

end
