class SharingService < ActiveRecord::Base
  belongs_to :user
  default_scope { order('lower(label)').where(sharing_type: 'custom') }

  def self.remove_access(user, service_id)
    unscoped.where(user: user, service_id: service_id).update_all(access_token: nil, access_secret: nil)
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
