class TouchActions
  include Sidekiq::Worker
  sidekiq_options queue: :search

  def perform(action_ids)
    actions = Action.find(action_ids)
    actions.each do |action|
      action.save
    end
  end
end
