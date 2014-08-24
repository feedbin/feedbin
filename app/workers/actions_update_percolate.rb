class ActionsUpdatePercolate
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform
    Action.find_each do |action|
      begin
        action.save
      rescue Exception
      end
    end
  end

end