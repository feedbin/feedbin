class SearchIndexStore
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  Logger = Sidekiq.logger.level == Logger::DEBUG ? Sidekiq.logger : nil
  Client = Elasticsearch::Client.new logger: Sidekiq.logger

  def perform(klass, id, update = false)
    klass = klass.constantize
    record = klass.find(id)

    Client.index  index: 'entries', type: 'entry', id: record.id, body: record.as_json

    # if !update
    #   percolator_ids = record.tire.index.percolate(record).map{ |match| match["_id"].to_i}
    #   if percolator_ids.present?
    #     ActionsPerform.perform_async(id, percolator_ids)
    #   end
    # end
  rescue ActiveRecord::RecordNotFound
  end

end