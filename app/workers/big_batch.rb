class BigBatch
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a

    Feed.where(id: ids).find_in_batches(batch_size: batch_size) do |feeds|
      feeds.each do |feed|
        most_recent_entry = Entry.select(:published).where(feed_id: feed.id).order('published DESC').limit(1).first
        if most_recent_entry.present?
          feed.last_published_entry = most_recent_entry.published
          feed.save
        end
      end
    end


  end


end