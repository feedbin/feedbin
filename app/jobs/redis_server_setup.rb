class RedisServerSetup
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  attr_reader :feed

  def perform(feed_id = nil, schedule = false)
    schedule ? build : index(feed_id)
  rescue ActiveRecord::RecordNotFound
  end

  def index(feed_id)
    @feed = Feed.find(feed_id)
    if feed.has_subscribers?
      insert_data
    else
      delete_data
    end
  end

  def insert_data
    return if values.first.empty?
    hash = Hash[keys.zip(values)]
    $redis[:entries].with do |redis|
      redis.multi do
        hash.each do |key, value|
          redis.del(key)
          redis.zadd(key, value)
        end
      end
    end
  end

  def delete_data
    $redis[:entries].with do |redis|
      keys.each {|key| redis.del(key)}
    end
  end

  def values
    @values ||= begin
      arrays = feed.entries.pluck("id, EXTRACT(EPOCH FROM created_at), EXTRACT(EPOCH FROM published)")
      [
        arrays.map {|array| [array[1], array[0]] },
        arrays.map {|array| [array[2], array[0]] }
      ]
    end
  end

  def keys
    [
      FeedbinUtils.redis_created_at_key(feed.id),
      FeedbinUtils.redis_published_key(feed.id)
    ]
  end

  def build
    enqueue_all(Feed, self.class)
  end
end
