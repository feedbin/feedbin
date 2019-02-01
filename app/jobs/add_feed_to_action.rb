class AddFeedToAction
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.find(user_id)
    actions = user.actions.where(all_feeds: true)
    actions.each do |action|
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
