class SupportedSharingService < ApplicationRecord
  SERVICES = [
    {
      service_id: "pocket",
      label: "Pocket",
      requires_auth: true,
      service_type: "oauth",
      klass: "Share::Pocket",
    },
    {
      service_id: "readability",
      label: "Readability",
      requires_auth: true,
      service_type: "xauth",
      klass: "Share::Readability",
      active: false,
    },
    {
      service_id: "instapaper",
      label: "Instapaper",
      requires_auth: true,
      service_type: "xauth",
      klass: "Share::Instapaper",
    },
    {
      service_id: "email",
      label: "Email",
      requires_auth: false,
      service_type: "email",
      html_options: {data: {behavior: "show_entry_basement", basement_panel: "email_share_panel"}},
      klass: "Share::Email",
      has_share_sheet: true,
      limit: 20,
    },
    {
      service_id: "kindle",
      label: "Kindle",
      requires_auth: false,
      service_type: "kindle",
      klass: "Share::Kindle",
    },
    {
      service_id: "pinboard",
      label: "Pinboard",
      requires_auth: true,
      service_type: "pinboard",
      html_options: {data: {behavior: "show_entry_basement", basement_panel: "pinboard_share_panel"}},
      klass: "Share::Pinboard",
      has_share_sheet: true,
    },
    {
      service_id: "tumblr",
      label: "Tumblr",
      requires_auth: true,
      service_type: "oauth",
      html_options: {data: {behavior: "show_entry_basement", basement_panel: "tumblr_share_panel"}},
      klass: "Share::Tumblr",
      has_share_sheet: true,
    },
    {
      service_id: "evernote",
      label: "Evernote",
      requires_auth: true,
      service_type: "oauth",
      html_options: {data: {behavior: "show_entry_basement", basement_panel: "evernote_share_panel"}},
      klass: "Share::EvernoteShare",
      has_share_sheet: true,
    },
    {
      service_id: "twitter",
      label: "Twitter",
      requires_auth: false,
      service_type: "popover",
      klass: "Share::Twitter",
    },
    {
      service_id: "facebook",
      label: "Facebook",
      requires_auth: false,
      service_type: "popover",
      klass: "Share::Facebook",
    },
    {
      service_id: "app_dot_net",
      label: "App.net",
      requires_auth: false,
      service_type: "popover",
      klass: "Share::AppDotNet",
      active: false,
    },
    {
      service_id: "buffer",
      label: "Buffer",
      requires_auth: false,
      service_type: "popover",
      klass: "Share::Buffer",
    },
    {
      service_id: "micro_blog",
      label: "Micro.blog",
      requires_auth: true,
      service_type: "micro_blog",
      html_options: {data: {behavior: "show_entry_basement", basement_panel: "micro_blog_share_panel"}},
      klass: "Share::MicroBlog",
      has_share_sheet: true,
    },
  ].freeze

  store_accessor :settings, :access_token, :access_secret, :email_name, :email_address,
    :kindle_address, :default_option, :api_token

  validates :service_id, presence: true, uniqueness: {scope: :user_id}, inclusion: {in: SERVICES.collect { |s| s[:service_id] }}
  belongs_to :user

  def share(params)
    key = "SupportedSharingService:share:#{user_id}:#{service_id}"

    result = if info[:limit]
      Throttle.throttle!(key, info[:limit], 1.hour) do
        service.share(params)
      end
    else
      service.share(params)
    end

    if result == false
      limit_exceeded
    else
      result
    end
  end

  def remove_access!
    update(access_token: nil, access_secret: nil)
  end

  # Hook that gets called after a service is successfully activated
  def after_activate
    result = service.try(:after_activate)
    if result.present?
      update(service_options: result)
    end
  end

  def service
    @service ||= klass.constantize.new(self)
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

  def link_options(entry)
    service_info = SupportedSharingService.info!(service_id)
    klass = service_info[:klass].constantize.new(self)
    klass.link_options(entry)
  end

  def self.info(service_id)
    SERVICES.find { |service| service[:service_id] == service_id }
  end

  def self.info!(service_id)
    data = info(service_id)
    if data.blank?
      raise ActionController::RoutingError.new("Not Found")
    end
    data
  end

  def info
    SERVICES.find { |service| service[:service_id] == service_id }
  end

  def html_options
    info[:html_options] || {remote: true}
  end

  def active?
    if info.key?(:active)
      info[:active]
    else
      true
    end
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

  def klass
    info[:klass]
  end

  def args
    info[:args]
  end

  def has_share_sheet?
    info[:has_share_sheet].present?
  end

  def auth_present?
    access_token.present?
  end

  def completions
    options = service_options || {}
    options["completions"] || []
  end

  def update_completions(new_completions)
    old_completions = completions
    final_completions = old_completions.concat(new_completions).uniq
    options = service_options || {}
    options["completions"] = final_completions
    update_attributes(service_options: nil)
    update_attributes(service_options: options)
  end

  def limit_exceeded
    Honeybadger.notify(
      error_class: "SupportedSharingService",
      error_message: "SupportedSharingService rate limit exceeded",
      parameters: {user_id: user_id},
    )
    {error: "Share limit exceeded"}
  end
end
