class SendExceptions
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(notice)
    Honeybadger.sender.send_to_honeybadger(notice)
  end
end