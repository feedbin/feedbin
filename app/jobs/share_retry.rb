class ShareRetry
  include Sidekiq::Worker

  def perform(service_id, params)
    sharing_service = SupportedSharingService.find(service_id)
    params = ActiveSupport::HashWithIndifferentAccess.new(params)
    sharing_service.service.share(params)
  rescue ActiveRecord::RecordNotFound
  end

end
