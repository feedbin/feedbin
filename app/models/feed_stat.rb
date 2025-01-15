class FeedStat < ApplicationRecord
  belongs_to :feed

  def self.daily_counts(feed_ids:, interval: "29 days")
    return {} if feed_ids.empty?
    sql = <<-SQL
    WITH dates AS (
      SELECT generate_series(
        CURRENT_DATE - INTERVAL :interval,
        CURRENT_DATE,
        '1 day'
      )::date AS day
    )
    SELECT results.feed_id, JSON_AGG(COALESCE(entries_count, 0) ORDER BY dates.day) as counts
    FROM dates
    CROSS JOIN (SELECT UNNEST(ARRAY[:feed_ids]) AS feed_id) results
    LEFT JOIN feed_stats ON feed_stats.day = dates.day AND feed_stats.feed_id = results.feed_id
    GROUP BY results.feed_id;
    SQL
    results = connection.execute(sanitize_sql_array([sql, interval: interval, feed_ids: feed_ids]))
    results.each_with_object({}) do |row, hash|
      counts = JSON.load(row["counts"])
      hash[row["feed_id"]] = Stat.new(counts)
    end
  end

  class Stat
    attr_reader :counts

    def initialize(counts)
      @counts = counts
    end

    def volume
      counts.sum
    end

    def percentages
      max = counts.max.to_i
      counts.map do |count|
        if count == 0
          0.to_f
        else
          count.to_f / max.to_f
        end
      end
    end
  end
end
