class TwitterAuth
  attr_reader :screen_name, :token, :secret
  def initialize(screen_name:, token:, secret:)
    @screen_name = screen_name
    @token       = token
    @secret      = secret
  end
end