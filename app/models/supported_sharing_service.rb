class SupportedSharingService < ActiveRecord::Base

  SERVICES = [
    {
      service_id: 'pocket',
      label: 'Pocket',
      requires_auth: true,
      service_type: 'oauth'
    },
    {
      service_id: 'readability',
      label: 'Readability',
      requires_auth: true,
      service_type: 'xauth'
    },
    {
      service_id: 'instapaper',
      label: 'Instapaper',
      requires_auth: true,
      service_type: 'xauth'
    },
    {
      service_id: 'email',
      label: 'Email',
      requires_auth: false,
      service_type: 'email',
      html_options: {data: {behavior: 'show_entry_basement', basement_panel: 'email_share_panel'}}
    }
  ].freeze

  store_accessor :settings, :access_token, :access_secret, :email_name, :email_address, :kindle_address
  validates :service_id, presence: true, uniqueness: {scope: :user_id}, inclusion: { in: SERVICES.collect {|s| s[:service_id]} }
  belongs_to :user


  def share(entry_id, params = {})
    entry = Entry.find(entry_id)
    self.send("share_with_#{service_id}", entry, params)
  end

  def share_with_pocket(entry, params)
    klass = Pocket.new(access_token)
    one_click_share(entry, klass)
  end

  def share_with_instapaper(entry, params)
    klass = Instapaper.new(access_token, access_secret)
    one_click_share(entry, klass)
  end

  def share_with_readability(entry, params)
    klass = Readability.new(access_token, access_secret)
    one_click_share(entry, klass)
  end

  def share_with_email(entry, params)
    UserMailer.delay(queue: :critical).entry(user_id, entry.id, params[:to], params[:subject], params[:body])
    {message: "Email sent to #{params[:to]}."}
  end

  def one_click_share(entry, klass)
    url = nil
    message = ''

    if active?
      status = klass.add(entry.fully_qualified_url)
      if status == 200
        message = "Link saved to #{label}."
      elsif status == 401
        remove_access!
        url = Rails.application.routes.url_helpers.sharing_services_path
        message = "#{label} authentication error."
      else
        message = "There was a problem connecting to #{label}."
      end
    else
      url = Rails.application.routes.url_helpers.sharing_services_path
      message = "#{label} authentication error."
    end

    {message: message, url: url}
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

  def self.info(service_id)
    SERVICES.find {|service| service[:service_id] == service_id}
  end

  def info
    SERVICES.find {|service| service[:service_id] == service_id}
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

  def html_options
    info[:html_options] || {remote: true}
  end

end
