class RemoveFeedFromAction
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, feed_id)
    user = User.find(user_id)
    actions = user.actions
    actions.each do |action|
      feed_ids = action.feed_ids || []
      action.feed_ids = feed_ids - [feed_id.to_s]
      action.status = if action.invalid?
        Action.statuses[:broken]
      else
        Action.statuses[:active]
      end
      action.automatic_modification = true
      action.save!
    end
  end
end
