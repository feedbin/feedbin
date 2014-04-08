class SharingService < ActiveRecord::Base
  SUPPORTED_SERVICES = [
    {
      label: 'Pocket',
      service_id: 'pocket',
      auth: :oauth2
    },
    {
      label: 'Readability',
      service_id: 'readability',
      auth: :xauth
    }
  ]

  belongs_to :user
  default_scope { order('lower(label)').where(sharing_type: 'custom') }

  def self.find_supported_service!(service_id)
    data = SUPPORTED_SERVICES.find {|supported_service| supported_service[:service_id] == service_id }
    raise ActiveRecord::RecordNotFound if data.nil?
    data
  end

  def self.remove_access(user, service_id)
    unscoped.where(user: user, service_id: service_id).update_all(access_token: nil, access_secret: nil)
  end
end
