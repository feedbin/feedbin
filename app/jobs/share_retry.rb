class ShareRetry
  include Sidekiq::Worker

  def perform(service_id, params)
    sharing_service = SupportedSharingService.find(service_id)
    params = ActiveSupport::HashWithIndifferentAccess.new(params)
    result = sharing_service.service.add(params)
    raise "ShareRetry failed" if result != 200
  rescue ActiveRecord::RecordNotFound
  end
end
