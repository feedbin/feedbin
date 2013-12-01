class SearchIndexRemove
  include Sidekiq::Worker

  def perform(klass, id)
    klass = klass.constantize.new
    klass.tire.index.remove({type: klass.tire.document_type, id: id})
  end

end