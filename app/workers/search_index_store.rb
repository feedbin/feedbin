class SearchIndexStore
  include Sidekiq::Worker

  def perform(klass, id)
    klass = klass.constantize
    record = klass.find(id)
    result = record.tire.index.store(record, {percolate: true})
    if result['matches'].present?
      matched_saved_search_ids = result['matches'].map{|match| match.to_i}
      ActionsPerform.perform_async(id, matched_saved_search_ids)
    end
  end

end