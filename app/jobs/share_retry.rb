class ShareRetry
  include Sidekiq::Worker

  def perform(service_id, params)
    sharing_service = SupportedSharingService.find(service_id)
    params = ActiveSupport::HashWithIndifferentAccess.new(params)
    result = sharing_service.service.add(params)
    if result == 401
      # An expired token fails the same way on every attempt; ask the user to
      # reconnect instead of burning the retry schedule.
      sharing_service.auth_error!
    elsif result != 200
      raise "ShareRetry failed"
    end
  rescue ActiveRecord::RecordNotFound
  end
end
