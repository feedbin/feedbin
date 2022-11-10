module Search
  class PercolateCreate
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    def perform(action_id)
      @action = Action.find(action_id)

      if @action.computed_feed_ids.empty?
        percolate_destroy
      elsif empty_notifier_action?
        percolate_destroy
      else
        $search[:main].with { _1.index(Action.table_name, id: @action.id, document: @action.search_body) }
      end
    end

    def empty_notifier_action?
      @action.all_feeds && @action.notifier? && @action.query.blank?
    end

    def percolate_destroy
      PercolateDestroy.perform_async(@action.id)
    end
  end
end