class BigBatch
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a

    ids.each do |feed_id|
      query = "SELECT date_trunc('day', published) as day, count(*) as entries_count FROM entries WHERE feed_id = ? AND published > ? GROUP BY day"
      query = ActiveRecord::Base.send(:sanitize_sql_array, [query, feed_id, 30.days.ago])
      results = ActiveRecord::Base.connection.execute(query)
      results.each do |result|
        updated_record_count = FeedStat.where(feed_id: feed_id, day: result['day']).update_all(entries_count: result['entries_count'])
        if updated_record_count == 0
          FeedStat.create(feed_id: feed_id, day: result['day'], entries_count: result['entries_count'])
        end
      end
    end


  end


end