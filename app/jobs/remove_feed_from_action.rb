class RemoveFeedFromAction
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, feed_id)
    user = User.find(user_id)
    actions = user.actions
    actions.each do |action|
      feed_ids = action.feed_ids || []
      action.feed_ids = feed_ids - [feed_id.to_s]
      if action.invalid?
        action.status = Action.statuses[:broken]
      else
        action.status = Action.statuses[:active]
      end
      action.automatic_modification = true
      action.save!
    end
  end
end
