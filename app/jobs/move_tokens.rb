class MoveTokens
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(user_id, original_name, new_name)
    user = User.find(user_id)
    token = user.send(original_name)
    user.authentication_tokens.create!(purpose: new_name, token: token)
  rescue ActiveRecord::RecordNotUnique
  end
end
