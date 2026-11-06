class BasicAuthentication
  def initialize(app)
    @app = app
  end

  # Old clients send bare base64 credentials; base64 has no whitespace, so a
  # header without any is that kind.
  def call(env)
    header = env["HTTP_AUTHORIZATION"]
    if header.is_a?(String) && !header.match?(/\s/)
      Rails.logger.info { "BasicAuthentication rewrote a bare Authorization header path=#{env["PATH_INFO"]} user_agent=#{env["HTTP_USER_AGENT"].inspect}" }
      env["HTTP_AUTHORIZATION"] = "Basic #{header}"
    end
    @app.call(env)
  end
end
