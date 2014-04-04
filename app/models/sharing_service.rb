class SharingService < ActiveRecord::Base
  NATIVE_SERVICES = [
    {
      label: 'Pocket',
      service_id: 'pocket',
    }
  ]

  belongs_to :user
  default_scope { order('lower(label)').where(group: 'custom') }

  def self.find_native_service!(service_id)
    data = NATIVE_SERVICES.find {|native_service| native_service[:service_id] == service_id }
    raise ActiveRecord::RecordNotFound if data.nil?
    data
  end
end
