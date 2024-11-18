class FeedStat < ApplicationRecord
  belongs_to :feed

  def self.daily_counts(feed_ids:, interval: "29 days")
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

  def self.get_entry_counts(feed_ids, start_date)
    end_date = Time.now

    stats_query = relative_entry_count_query

    entry_counts = {}
    feed_ids.each do |feed_id|
      query = ActiveRecord::Base.send(:sanitize_sql_array, [stats_query, start_date, end_date, start_date, feed_id])
      results = ActiveRecord::Base.connection.execute(query)
      results.each do |result|
        if entry_counts.key?(feed_id)
          entry_counts[feed_id] << result["entries_count"].to_i
        else
          entry_counts[feed_id] = [result["entries_count"].to_i]
        end
      end
    end
    entry_counts
  end

  def self.max_entry_count(feed_ids, start_date)
    max_query = "SELECT COALESCE(MAX(entries_count), 0) as max FROM feed_stats WHERE feed_id IN(?) and day >= ?"
    max_query = ActiveRecord::Base.send(:sanitize_sql_array, [max_query, feed_ids, start_date])
    max = ActiveRecord::Base.connection.execute(max_query)
    max.first["max"].to_i
  end

  def self.relative_entry_count_query
    <<-eos
      SELECT
        date,
        coalesce(entries_count,0) AS entries_count
      FROM
      generate_series(
        ?::date,
        ?::date,
        '1 day'
      ) AS date
      LEFT OUTER JOIN (
        SELECT
        day,
        entries_count
        FROM feed_stats
        WHERE day >= ?
        AND feed_id = ?
      ) results
      ON (date = results.day)
    eos
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
