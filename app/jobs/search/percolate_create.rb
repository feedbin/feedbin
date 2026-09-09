module Search
  class PercolateCreate
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    # The mirror of PercolateDestroy.for_users, for reactivation: the action
    # rows survive a suspension untouched, so re-registering rebuilds the
    # same percolators.
    def self.for_users(user_ids)
      Action.where(user_id: user_ids).pluck(:id).each { |action_id| perform_async(action_id) }
    end

    # Enqueued from an after_commit, so a create followed quickly by a destroy
    # leaves a job for an id that is already gone. PercolateDestroy has its own
    # job; there is nothing to do here.
    def perform(action_id)
      return unless @action = Action.find_by(id: action_id)

      if @action.user.suspended?
        # A suspended account must have no percolators. Routing the create to
        # a destroy makes the invariant self-heal: an action saved through
        # any path while the account is suspended converts to a removal, and
        # User#activate re-registers everything when the account returns.
        percolate_destroy
      elsif @action.computed_feed_ids.empty?
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