require 'clockwork'
require_relative '../config/boot'
require_relative '../config/environment'

include Clockwork

# Use locks so multiple clock processes do not schedule dupes
every(1.minutes, 'run_clockwork') {

  if RedisLock.acquire("clockwork:feed:refresher:scheduler", 25.minutes.to_i)
    FeedRefresherScheduler.perform_async
  end

  if RedisLock.acquire("clockwork:send_stats", 55)
    SendStats.perform_async
  end

  if RedisLock.acquire("clockwork:delete_unread_entries", 1.day.to_i)
    UnreadEntryDeleter.perform_async
  end

  if RedisLock.acquire("clockwork:delete_entries", 1.day.to_i)
    EntryDeleterScheduler.perform_async
  end
}
