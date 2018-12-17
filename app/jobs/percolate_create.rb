class PercolateCreate
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(action_id)
    @action = Action.find(action_id)

    if @action.computed_feed_ids.empty?
      percolate_destroy
    elsif empty_notifier_action?
      percolate_destroy
    else
      options = {
        index: Entry.index_name,
        type: ".percolator",
        id: @action.id,
        body: @action.search_body,
      }
      $search.each do |_, client|
        client.index(options)
      end
    end
  end

  def empty_notifier_action?
    @action.all_feeds && @action.notifier? && (@action.query.nil? || @action.query == "")
  end

  def percolate_destroy
    PercolateDestroy.perform_async(@action.id)
  end
end
