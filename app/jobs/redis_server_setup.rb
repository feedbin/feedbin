class RedisServerSetup
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :default

  def perform(batch = nil, schedule = false, last_entry_id = nil)
    if schedule
      build(last_entry_id)
    else
      index(batch)
    end
  end

  def index(batch)
    ids = build_ids(batch)
    entries = Entry.where(id: ids).select("id, feed_id, public_id, EXTRACT(EPOCH FROM created_at AT TIME ZONE 'UTC') as score_created_at, EXTRACT(EPOCH FROM published AT TIME ZONE 'UTC') as score_published")
    $redis[:sorted_entries].with do |redis|
      redis.pipelined do
        entries.each do |entry|
          key1 = FeedbinUtils.redis_feed_entries_created_at_key(entry.feed_id)
          redis.zadd(key1, entry.score_created_at, entry.id)

          key2 = FeedbinUtils.redis_feed_entries_published_key(entry.feed_id)
          redis.zadd(key2, entry.score_published, entry.id)
        end
      end
    end
  end

  def build(last_entry_id)
    jobs = job_args(last_entry_id)
    Sidekiq::Client.push_bulk(
      "args" => jobs,
      "class" => self.class.name,
      "queue" => self.class.get_sidekiq_options["queue"].to_s,
    )
  end
end
