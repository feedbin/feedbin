class SearchIndexStore
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(klass, id, update = false)
    klass = klass.constantize
    record = klass.find(id)
    record.tire.index.store(record)
    if !update
      percolator_ids = record.tire.index.percolate(record).map{ |match| match["_id"].to_i}
      if percolator_ids.present?
        ActionsPerform.perform_async(id, percolator_ids)
      end
    end
  end

end