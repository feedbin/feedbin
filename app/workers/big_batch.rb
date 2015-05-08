class BigBatch
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a

    $redis.pipelined do
      Entry.where(id: ids).pluck('id, feed_id, public_id, extract(epoch from created_at), extract(epoch from published)').each do |(id, feed_id, public_id, created_at, published)|
        # entry_id, feed_id, public_id, created_at, published
        key = FeedbinUtils.redis_feed_entries_created_at_key(feed_id)
        $redis.zadd(key, created_at, id)

        key = FeedbinUtils.redis_feed_entries_published_key(feed_id)
        $redis.zadd(key, published, id)
      end
    end

  end

end