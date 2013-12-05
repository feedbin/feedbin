class SearchIndexStore
  include Sidekiq::Worker

  def perform(klass, id, update = false)
    klass = klass.constantize
    record = klass.find(id)
    if update
      record.tire.index.store(record)
    else
      result = record.tire.index.store(record, {percolate: true})
      if result['matches'].present?
        matched_saved_search_ids = result['matches'].map{|match| match.to_i}
        ActionsPerform.perform_async(id, matched_saved_search_ids)
      end
    end
  end

end