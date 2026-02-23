class Turnstile
  VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  def self.verify(response, remoteip: nil)
    return false if response.blank?

    params = {
      secret: ENV["TURNSTILE_SECRET_KEY"],
      response: response,
    }
    params[:remoteip] = remoteip if remoteip.present?

    result = HTTP.post(VERIFY_URL, form: params).parse
    result["success"] == true
  rescue
    false
  end
end
