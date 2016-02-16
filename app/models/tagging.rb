class Tagging < ActiveRecord::Base
  belongs_to :tag
  belongs_to :feed
  belongs_to :user

  after_commit :update_actions, on: [:create, :destroy]

  def update_actions
    actions = self.user.actions.where("? = ANY (tag_ids)", tag_id).pluck(:id)
    TouchActions.perform_async(actions)
  end

end
