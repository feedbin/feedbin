class MoveNewsletterTokens < ActiveRecord::Migration[6.0]
  include BatchJobs

  def up
    enqueue_all(User, MoveTokens, "newsletter_token", "newsletters")
  end

  def down
  end
end
