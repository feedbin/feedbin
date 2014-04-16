class SharingService < ActiveRecord::Base

  store_accessor :settings, :access_token, :access_secret

  belongs_to :user
  default_scope { order('lower(label)').where(sharing_type: 'custom') }

  def self.remove_access(user, service_id)
    unscoped.where(user: user, service_id: service_id).first.update(access_token: nil, access_secret: nil)
  end

  def self.create_or_update_supported_service(user, supported_sharing_service, options = {})
    defaults = {label: supported_sharing_service.label, sharing_type: "supported", service_id: supported_sharing_service.service_id}
    supported_service = unscoped.find_or_initialize_by(user: user, service_id: supported_sharing_service.service_id)
    supported_service.update(defaults.merge(options))
  end

  def supported_sharing_service_info
    SupportedSharingService.find(service_id)
  end

  def auth_present?
    access_token.present?
  end

  def active?
    if supported_sharing_service_info.requires_auth? && auth_present?
      true
    elsif supported_sharing_service_info.requires_auth?
      false
    else
      true
    end
  end

end
