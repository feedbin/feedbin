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
        percolate_format: 'ids',
        body: {
          doc: record.as_indexed_json,
          filter: {
            term: { feed_id: record.feed_id }
          }
        }
      )
      percolator_ids = result['matches'].map(&:to_i)
      if percolator_ids.present?
        ActionsPerform.perform_async(id, percolator_ids)
      end
    end
  rescue ActiveRecord::RecordNotFound
  end

end