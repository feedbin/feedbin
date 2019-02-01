class FeedStat < ApplicationRecord
  belongs_to :feed

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
end
