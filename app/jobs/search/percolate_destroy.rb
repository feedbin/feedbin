module Search
  class PercolateDestroy
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    def perform(action_id)
      $search[:main].with { _1.delete(Action.table_name, id: action_id) }
    end
  end
end