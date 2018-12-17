class ActionTags
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, tag_id, tag_id_was)
    user = User.find(user_id)
    actions = user.actions.where("? = ANY (tag_ids)", tag_id_was)
    actions.each do |action|
      if tag_id_was.present?
        action.tag_ids = action.tag_ids - [tag_id_was]
      end

      if tag_id.present?
        action.tag_ids = action.tag_ids + [tag_id]
      end

      action.save
    end
  end
end
