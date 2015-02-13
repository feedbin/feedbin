class EntryIdCache
  def initialize(user_id, feed_ids, page)
    @user_id = user_id
    @feed_ids = [*feed_ids]
    if page
      @page = page.to_i
    else
      @page = 1
    end
  end

  def cache_key
    if @feed_ids.length == 1
      FeedbinUtils.redis_feed_entries_published_key(@feed_ids.first)
    else
      FeedbinUtils.redis_user_entries_published_key(@user_id, @feed_ids)
    end
  end

  def entries
    user = User.find(@user_id)

    start = (@page - 1) * WillPaginate.per_page
    stop = start + WillPaginate.per_page - 1

    key_exists, entry_ids = $redis.multi do
      $redis.exists(cache_key)
      $redis.zrevrange(cache_key, start, stop)
    end

    if !key_exists

      keys = @feed_ids.map do |feed_id|
        FeedbinUtils.redis_feed_entries_published_key(feed_id)
      end

      count, expire, entry_ids = $redis.multi do
        $redis.zunionstore(cache_key, keys)
        $redis.expire(cache_key, 2.minutes.to_i)
        $redis.zrevrange(cache_key, start, stop)
      end

    end
    Entry.where(id: entry_ids).includes(:feed).sort_preference('DESC').entries_list
  end


  def page_query
    WillPaginate::Collection.new(@page, WillPaginate.per_page, $redis.zcard(cache_key))
  end
end