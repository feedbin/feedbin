module Search
  class PercolateDestroy
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    # Every action the given users own, one job each. The suspension
    # lifecycle uses this: a suspended account must have no percolators, or
    # its actions keep firing on every matching entry. Deleting a percolator
    # that is already gone is a no-op, so this is safe to re-run.
    def self.for_users(user_ids)
      Action.where(user_id: user_ids).pluck(:id).each { |action_id| perform_async(action_id) }
    end

    def perform(action_id)
      Search.client(mirror: true) { _1.delete(Search.index_name(Action.table_name), id: action_id) }
    end
  end
end