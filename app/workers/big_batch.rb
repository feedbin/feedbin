class BigBatch
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a


    Sidekiq.redis do |conn|
      conn.pipelined do
        Entry.where(id: ids).each do |entry|
          content_length = entry.content ? entry.content.length : 1
          conn.hset("entry:public_ids:#{entry.public_id[0..4]}", entry.public_id, content_length)
        end
      end
    end


  end


end