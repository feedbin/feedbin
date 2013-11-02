class SearchIndexStore
  include Sidekiq::Worker

  def perform(klass, id)
    klass = klass.constantize
    record = klass.find(id)
    record.tire.index.store(record)
    if record.respond_to?(:feed_id)
      # Wait a bit to make sure it's indexed
      ActionsPerform.perform_in(5.seconds, id, record.feed_id)
    end
  end

end