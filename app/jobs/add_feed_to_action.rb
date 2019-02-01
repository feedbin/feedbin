class AddFeedToAction
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.find(user_id)
    actions = user.actions.where(all_feeds: true)
    actions.each do |action|
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
