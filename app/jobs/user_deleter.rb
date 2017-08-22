class UserDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.find(user_id)
    user.destroy
  end

end