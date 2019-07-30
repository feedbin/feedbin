class EntryIdCache
  attr_reader :user_id, :feed_ids, :page_number, :ids

  def initialize(user_id, feed_ids)
    @user_id = user_id
    @feed_ids = [*feed_ids]
    @ids = {}
  end

  def page(number = nil)
    @page_number = number ? number.to_i : 1
    ids = get_ids
    WillPaginate::Collection.create(page_number, per_page, count) do |pager|
      pager.replace Entry.where(id: ids).includes(feed: [:favicon]).sort_preference("DESC").entries_list
    end
  end

  private

  def count
    $redis[:entries].with do |redis|
      redis.zcard(cache_key)
    end
  end

  def per_page
    WillPaginate.per_page
  end

  def user
    @user ||= User.find(user_id)
  end

  def cache_key
    if feed_ids.length == 1
      FeedbinUtils.redis_published_key(feed_ids.first)
    else
      FeedbinUtils.redis_user_entries_published_key(user_id, feed_ids)
    end
  end

  def get_ids
    ids[page_number] ||= begin
      key_exists, entry_ids = $redis[:entries].with { |redis|
        redis.multi do
          redis.exists(cache_key)
          redis.zrevrange(cache_key, start, stop)
        end
      }

      unless key_exists
        keys = feed_ids.map { |feed_id|
          FeedbinUtils.redis_published_key(feed_id)
        }
        count, expire, entry_ids = $redis[:entries].with { |redis|
          redis.multi do
            redis.zunionstore(cache_key, keys)
            redis.expire(cache_key, 2.minutes.to_i)
            redis.zrevrange(cache_key, start, stop)
          end
        }
      end
      entry_ids
    end
  end

  def start
    (page_number - 1) * WillPaginate.per_page
  end

  def stop
    start + WillPaginate.per_page - 1
  end
end
