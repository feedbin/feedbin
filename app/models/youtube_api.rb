# The YouTube Data API. A lookup answers the items YouTube returned, or nil
# when the request failed.
#
# A refused request pauses harvesting for 5 minutes, then 10, 20, 40, up to an
# hour, and the next success starts over. Nothing is assumed about YouTube's
# limits or when they reset: a refused request costs no quota, so asking again
# later is free.
class YoutubeApi
  # Named for the job these keys were first written by.
  PAUSE_KEY = "HarvestEmbeds-paused"
  # How many pauses in a row; a successful request clears it.
  BACKOFF_KEY = "HarvestEmbeds-backoff"
  FIRST_PAUSE = 5.minutes
  LONGEST_PAUSE = 1.hour

  class << self
    def videos(ids)
      items("videos", ids, "snippet,contentDetails,liveStreamingDetails")
    end

    def channels(ids)
      items("channels", ids, "snippet,statistics,brandingSettings")
    end

    def paused?
      Sidekiq.redis { it.call("EXISTS", PAUSE_KEY) } == 1
    end

    private

    # Not through UrlCache: a redownload has to see the stream's current state.
    def items(type, ids, part)
      return [] if ids.empty?

      response = HTTP.timeout(write: 5, connect: 5, read: 10)
        .get("https://www.googleapis.com/youtube/v3/#{type}", params: {key: ENV["YOUTUBE_KEY"], part:, id: ids.join(",")})
      body = response.to_s

      if response.status.success?
        reset_backoff
        # Deleted, private and region-blocked videos come back with no "items".
        without_nul(JSON.parse(body))["items"] || []
      else
        Sidekiq.logger.info "HarvestEmbeds youtube_api failed type=#{type} status=#{response.status.code} body=#{body[0, 500].squish}"
        back_off if refused?(response.status.code, body)
        nil
      end
    rescue HTTP::Error, OpenSSL::SSL::SSLError
      nil
    end

    # YouTube answers 403 quotaExceeded or rateLimitExceeded (also
    # userRateLimitExceeded); Google's front end can answer 429.
    def refused?(status, body)
      status == 429 || (status == 403 && body.match?(/quotaExceeded|rateLimitExceeded/i))
    end

    # The batches already sent are refused together; only the first refusal
    # lengthens the pause.
    def back_off
      Sidekiq.redis do |redis|
        next unless redis.call("SET", PAUSE_KEY, "1", "NX", "EX", LONGEST_PAUSE.to_i)
        step = redis.call("INCR", BACKOFF_KEY)
        redis.call("EXPIRE", BACKOFF_KEY, 1.day.to_i)
        redis.call("EXPIRE", PAUSE_KEY, [FIRST_PAUSE * 2**(step - 1), LONGEST_PAUSE].min.to_i)
      end
    end

    def reset_backoff
      Sidekiq.redis { it.call("DEL", BACKOFF_KEY) }
    end

    # jsonb refuses \u0000, and one in a channel's description failed the
    # whole batch's import.
    def without_nul(value)
      case value
      when String then value.delete("\u0000")
      when Array then value.map { without_nul(it) }
      when Hash then value.to_h { [without_nul(_1), without_nul(_2)] }
      else value
      end
    end
  end
end
