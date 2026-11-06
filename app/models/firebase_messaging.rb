# FCM HTTP v1 sender, authorized as the service account whose JSON key is at FIREBASE_CREDENTIALS.
class FirebaseMessaging
  SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
  GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer"

  class Error < StandardError; end

  Response = Data.define(:status, :error_code) do
    def success? = status.between?(200, 299)

    def unregistered? = status == 404 || error_code == "UNREGISTERED"
  end

  def initialize(credentials_path = ENV["FIREBASE_CREDENTIALS"])
    @credentials_path = credentials_path
    @lock = Mutex.new
  end

  def configured? = @credentials_path.present?

  def deliver(message)
    response = client.auth("Bearer #{access_token}").post(send_url, json: {message: message})
    Response.new(status: response.code, error_code: error_code(response))
  end

  private

  def client = HTTP.timeout(connect: 5, write: 5, read: 10)

  def send_url = "https://fcm.googleapis.com/v1/projects/#{credentials.fetch("project_id")}/messages:send"

  def credentials
    @credentials ||= JSON.parse(File.read(@credentials_path))
  end

  def access_token
    @lock.synchronize do
      refresh_access_token if @access_token.nil? || @expires_at < 1.minute.from_now
      @access_token
    end
  end

  def refresh_access_token
    response = client.post(credentials.fetch("token_uri"), form: {grant_type: GRANT_TYPE, assertion: assertion})
    raise Error, "Token request failed: #{response.code}" unless response.status.success?
    body = JSON.parse(response.to_s)
    @access_token = body.fetch("access_token")
    @expires_at = body.fetch("expires_in").to_i.seconds.from_now
  end

  def assertion
    now = Time.now.to_i
    claims = {iss: credentials.fetch("client_email"), scope: SCOPE, aud: credentials.fetch("token_uri"), iat: now, exp: now + 3600}
    JWT.encode(claims, OpenSSL::PKey::RSA.new(credentials.fetch("private_key")), "RS256")
  end

  def error_code(response)
    return if response.status.success?
    details = JSON.parse(response.to_s).dig("error", "details") || []
    details.filter_map { |detail| detail["errorCode"] }.first
  rescue JSON::ParserError
    nil
  end
end
