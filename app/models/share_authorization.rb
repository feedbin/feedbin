# An app connecting a share service through the user's browser, with no web session: a signed state ties the
# service's callback to the user, the service and the app's address to come back to. OAuth 2 services carry it as
# `state`; OAuth 1 services can't, so their request token is kept in the cache with it.
class ShareAuthorization
  EXPIRY = 15.minutes

  class Invalid < StandardError; end

  attr_reader :user, :service_id, :return_to

  def self.verifier
    Rails.application.message_verifier("share_authorization")
  end

  # The page the app opens: the service's own sign-in.
  def self.start(user, service_id, return_to:, mastodon_host: nil)
    info = SupportedSharingService.info!(service_id)
    state = verifier.generate({user_id: user.id, service_id: service_id, return_to: return_to}, expires_in: EXPIRY)
    service = info.klass.constantize.new
    case info.service_type
    when "oauth2"
      service.authorize_redirect({mastodon_url: mastodon_host}.with_indifferent_access, state)
    when "oauth"
      token = service.request_token
      raise Invalid, "#{info.label} gave no request token." unless token.token && token.secret
      Rails.cache.write(cache_key(token.token), {state: state, secret: token.secret}, expires_in: EXPIRY)
      token.authorize_url
    else
      raise Invalid, "#{info.label} doesn't sign in through the browser."
    end
  end

  def self.find(state)
    data = verifier.verified(state.to_s) or return
    user = User.find_by(id: data["user_id"]) or return
    new(user, data["service_id"], data["return_to"])
  end

  # An OAuth 1 callback's: the state and secret its request token was kept with.
  def self.find_oauth1(token)
    kept = Rails.cache.read(cache_key(token.to_s)) or return
    find(kept[:state])&.tap { _1.secret = kept[:secret] }
  end

  def self.cache_key(token) = "share_authorization:#{token}"

  attr_accessor :secret

  def initialize(user, service_id, return_to)
    @user = user
    @service_id = service_id
    @return_to = return_to
  end

  # The app's address with how it went: `active`, `declined` or `failed`.
  def complete_oauth2(params)
    return return_url("declined") if params[:code].blank?
    save(service.request_access(params))
  rescue Share::Service::AuthError, OAuth2::Error
    return_url("failed")
  end

  def complete_oauth1(params)
    return return_url("declined") if params[:oauth_verifier].blank?
    Rails.cache.delete(self.class.cache_key(params[:oauth_token]))
    token = service.request_access(params[:oauth_token], secret, params[:oauth_verifier])
    save(access_token: token.token, access_secret: token.secret)
  rescue OAuth::Unauthorized, OAuth::Error
    return_url("failed")
  end

  def return_url(status)
    uri = URI.parse(return_to)
    uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s) + [["service_id", service_id], ["status", status]])
    uri.to_s
  end

  private

  def service
    SupportedSharingService.info!(service_id).klass.constantize.new
  end

  def save(attributes)
    record = user.supported_sharing_services.where(service_id: service_id).first_or_initialize
    return return_url("failed") unless record.update(attributes)
    record.ok!
    record.try(:after_activate)
    return_url("active")
  end
end
