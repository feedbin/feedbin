class BigBatch
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a

    entries = Entry.where(id: ids)

    Tire.index("entries").import(entries)
  end

end