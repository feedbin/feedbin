class SupportedSharingService < ActiveRecord::Base
  store_accessor :settings, :access_token, :access_secret, :email_name, :email_address, :kindle_address
  validates :service_id, presence: true, uniqueness: {scope: :user_id}, inclusion: { in: Feedbin::Application.config.supported_services.collect {|s| s[:service_id]} }
  belongs_to :user

  def share(entry_id)
    entry = Entry.find(entry_id)

    if active?
      if service_id == 'pocket'
        klass = Pocket.new(access_token)
      elsif service_id == 'readability'
        klass = Readability.new(access_token, access_secret)
      elsif service_id == 'instapaper'
        klass = Instapaper.new(access_token, access_secret)
      end
      response = klass.add(entry.fully_qualified_url)
      if response == 401
        remove_access!
      end
    else
      response = 401
    end

    response
  end

  def remove_access!
    update(access_token: nil, access_secret: nil)
  end

  def active?
    if requires_auth? && auth_present?
      true
    elsif requires_auth?
      false
    else
      true
    end
  end

  def info
    @info ||= Feedbin::Application.config.supported_services.find {|option| option[:service_id] = service_id}
  end

  def label
    info[:label]
  end

  def requires_auth?
    info[:requires_auth]
  end

  def service_type
    info[:service_type]
  end

  def auth_present?
    access_token.present?
  end

end
