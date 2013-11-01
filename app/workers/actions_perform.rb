class ActionsPerform
  include Sidekiq::Worker

  def perform(entry_id, feed_id)
    actions = Rails.cache.fetch("actions:all", expires_in: 5.minutes) do
      actions = Action.all
    end

    actions = Action.all

    actions = actions.keep_if do |action|
      action.feed_ids.empty? || action.feed_ids.include?(entry.feed_id.to_s)
    end

    Rails.logger.info { "-------------------------" }
    Rails.logger.info { actions.inspect }
    Rails.logger.info { "-------------------------" }

    actions.each do |action|
      results = Entry.action_search(action.query, entry_id)
    end

  end

end