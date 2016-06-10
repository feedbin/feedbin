class SearchIndexStore
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(klass, id, update = false)
    klass = klass.constantize
    record = klass.find(id)
    record.__elasticsearch__.index_document
    if !update
      result = klass.__elasticsearch__.client.percolate(
        index: klass.index_name,
        type: klass.document_type,
        body: {doc: record.as_indexed_json}
      )
      percolator_ids = result['matches'].map{ |match| match["_id"].to_i }
      if percolator_ids.present?
        ActionsPerform.perform_async(id, percolator_ids)
      end
    end
  rescue ActiveRecord::RecordNotFound
  end

end