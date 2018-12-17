module RedisCache
  extend ActiveSupport::Concern

  def get_cached_entry_ids(cache_key, feed_key, since = "-inf", read = nil, starred = nil)
    key_exists, entry_ids = $redis[:sorted_entries].with do |redis|
      redis.multi do
        redis.exists(cache_key)
        redis.lrange(cache_key, 0, -1)
      end
    end

    unless key_exists
      feed_ids = @user.subscriptions.pluck(:feed_id)

      keys = feed_ids.map do |feed_id|
        feed_key % feed_id
      end

      scores = $redis[:sorted_entries].with do |redis|
        redis.pipelined do
          keys.each do |key|
            redis.zrangebyscore(key, since, "+inf", with_scores: true)
          end
        end
      end

      scores = scores.flatten(1)
      scores = scores.sort_by { |score| score[1] }.reverse

      entry_ids = scores.map { |(feed_id, _)| feed_id.to_i }

      if "false" == starred
        starred_entry_ids = @user.starred_entries.pluck(:entry_id)
        entry_ids = entry_ids - starred_entry_ids
      end

      if ["true", "false"].include?(read)
        unread_entry_ids = @user.unread_entries.pluck(:entry_id)
        if "false" == read
          entry_ids = entry_ids & unread_entry_ids
        elsif "true" == read
          entry_ids = entry_ids - unread_entry_ids
        end
      end

      cache_entry_ids(cache_key, entry_ids)
    end

    entry_ids.map(&:to_i)
  end

  def build_pagination(entry_ids)
    options = {}
    if params[:page]
      options[:page] = params[:page].to_i
    else
      options[:page] = 1
    end

    if params[:per_page]
      options[:per_page] = params[:per_page].to_i
    else
      options[:per_page] = WillPaginate.per_page
    end

    options[:paged_entry_ids] = entry_ids.each_slice(options[:per_page]).to_a
    options[:will_paginate] = WillPaginate::Collection.new(options[:page], options[:per_page], entry_ids.length)
    options[:page_index] = options[:page] - 1
    options
  end

  def cache_entry_ids(cache_key, entry_ids)
    if entry_ids.present?
      $redis[:sorted_entries].with do |redis|
        redis.multi do
          redis.del(cache_key)
          redis.rpush(cache_key, entry_ids)
          redis.expire(cache_key, 2.minutes.to_i)
        end
      end
    end
  end
end
