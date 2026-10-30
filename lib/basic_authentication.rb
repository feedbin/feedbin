class BasicAuthentication
  def initialize(app)
    @app = app
  end

  # Old clients send bare base64 credentials with no scheme. Base64 has no
  # whitespace and every scheme is followed by a space (Basic, Bearer,
  # ApplePushNotifications), so a header without whitespace is the bare kind.
  def call(env)
    header = env["HTTP_AUTHORIZATION"]
    if header.is_a?(String) && !header.match?(/\s/)
      env["HTTP_AUTHORIZATION"] = "Basic #{header}"
    end
    @app.call(env)
  end
end
