module Search
  class TouchActions
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    # find raises unless every id resolves, and it raises before touching any
    # of them — so one action destroyed between the enqueue and the perform
    # would cost the whole batch its percolator refresh.
    def perform(action_ids)
      Action.where(id: action_ids).find_each do |action|
        action.save
      end
    end
  end
end