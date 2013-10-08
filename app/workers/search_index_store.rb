class SearchIndexStore
  include Sidekiq::Worker
  
  def perform(klass, id)
    klass = klass.constantize
    record = klass.find(id)
    record.tire.index.store(record)
  end
  
end