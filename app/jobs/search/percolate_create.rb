module Search
  class PercolateCreate
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    # Enqueued from an after_commit, so a create followed quickly by a destroy
    # leaves a job for an id that is already gone. PercolateDestroy has its own
    # job; there is nothing to do here.
    def perform(action_id)
      return unless @action = Action.find_by(id: action_id)

      if @action.computed_feed_ids.empty?
        percolate_destroy
      elsif empty_notifier_action?
        percolate_destroy
      else
        Search.client(mirror: true) { _1.index(Search.index_name(Action.table_name), id: @action.id, document: @action.search_body) }
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